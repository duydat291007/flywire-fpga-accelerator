// mvu_systolic.sv
// Weight-stationary systolic matrix-vector unit. Port-compatible with
// mvu_serial; behavior specified in docs/specification.md section 2.
//
// Work decomposition for dim = n:
//   NOG = ceil(n / COLS) output groups, NIG = ceil(n / ROWS) input groups.
//   Tiles are processed og-major, ig-minor: (og=0,ig=0), (0,1) ... (NOG-1,NIG-1).
//   Tile (og, ig) puts W[og*COLS + c][ig*ROWS + r] into PE[r][c].
//
// Three concurrent agents, all in the RUN state:
//   Loader    reads the tile's weights (1 per cycle if BANKED=0, one PE row =
//             COLS weights per cycle if BANKED=1) into weight buffer k % WBUF.
//             It may start tile k only when that buffer is free.
//   Launcher  once tile k is loaded, reads x[ig*ROWS + r] for every row and
//             sends one skewed wavefront into the array, tagged with its buffer
//             index and {og, first_ig, last_ig}.
//   Collector accumulates each column's partial sums across the NIG tiles of
//             an output group and writes finished results to the result
//             buffer. Column COLS-1 finishing a tile frees its weight buffer.
//
// Out-of-range rows/columns of partial tiles are zeroed at load/launch time, so
// memory contents outside dim can never reach a result.
// See docs/architecture.md for the cycle-level schedule.

`timescale 1ns/1ps

module mvu_systolic #(
    parameter int N_MAX  = 64,
    parameter int ROWS   = 4,
    parameter int COLS   = 4,
    parameter int BANKED = 1,
    parameter int WBUF   = 2
) (
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     w_valid,
    output logic                     w_ready,
    input  logic [$clog2(N_MAX)-1:0] w_dst,
    input  logic [$clog2(N_MAX)-1:0] w_src,
    input  logic [7:0]               w_data,

    input  logic                     x_valid,
    output logic                     x_ready,
    input  logic [$clog2(N_MAX)-1:0] x_idx,
    input  logic [7:0]               x_data,

    input  logic                     xb_valid,
    output logic                     xb_ready,
    input  logic [N_MAX-1:0]         xb_bits,

    input  logic                     cmd_valid,
    output logic                     cmd_ready,
    input  logic [$clog2(N_MAX):0]   cmd_dim,

    output logic                     res_valid,
    input  logic                     res_ready,
    output logic [31:0]              res_data,
    output logic [$clog2(N_MAX)-1:0] res_idx,
    output logic                     res_last,

    output logic                     busy,
    output logic                     done,
    output logic                     err_dim
);

    // ------------------------------------------------------------------
    // Derived parameters
    // ------------------------------------------------------------------
    localparam int AW     = $clog2(N_MAX);
    localparam int DW     = AW + 1;
    localparam int RW     = (ROWS <= 1) ? 1 : $clog2(ROWS);
    localparam int CW     = (COLS <= 1) ? 1 : $clog2(COLS);
    localparam int LOG_R  = $clog2(ROWS);
    localparam int LOG_C  = $clog2(COLS);
    localparam int NOG_MAX = N_MAX / COLS;
    localparam int NIG_MAX = N_MAX / ROWS;
    localparam int OGW    = (NOG_MAX <= 1) ? 1 : $clog2(NOG_MAX);
    localparam int IGW    = (NIG_MAX <= 1) ? 1 : $clog2(NIG_MAX);
    localparam int TW     = $clog2(NOG_MAX * NIG_MAX + 1);      // tile counter width
    localparam int SEL_W  = (WBUF <= 1) ? 1 : $clog2(WBUF);
    localparam int TAG_W  = OGW + 2;                           // {og, first, last}
    localparam int NB     = (BANKED != 0) ? COLS : 1;
    localparam int LAW    = $clog2(N_MAX * N_MAX / NB);
    localparam int LSTEPS = (BANKED != 0) ? ROWS : ROWS * COLS; // load cycles per tile
    localparam int LSW    = (LSTEPS <= 1) ? 1 : $clog2(LSTEPS);

    // Elaboration-time sanity checks
    initial begin
        if ((1 << LOG_R) != ROWS || (1 << LOG_C) != COLS)
            $fatal(1, "ROWS and COLS must be powers of two");
        if (N_MAX % ROWS != 0 || N_MAX % COLS != 0)
            $fatal(1, "ROWS and COLS must divide N_MAX");
        if (WBUF < 1 || WBUF > 4)
            $fatal(1, "WBUF must be 1..4");
    end

    // ------------------------------------------------------------------
    // Top-level control
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DRAIN} state_t;
    state_t state;

    logic [DW-1:0] dim_q;
    logic [IGW:0]  nig_q;        // number of input groups
    logic [TW-1:0] total_q;      // tiles in this operation

    assign busy      = (state != S_IDLE);
    assign cmd_ready = !busy;
    assign w_ready   = !busy;
    assign x_ready   = !busy;
    assign xb_ready  = !busy;

    wire cmd_fire = cmd_valid && cmd_ready;
    wire dim_ok   = (cmd_dim != '0) && (cmd_dim <= DW'(N_MAX));

    // ceil(dim / COLS), ceil(dim / ROWS)
    wire [DW:0] nog_calc = ({1'b0, cmd_dim} + DW'(COLS - 1)) >> LOG_C;
    wire [DW:0] nig_calc = ({1'b0, cmd_dim} + DW'(ROWS - 1)) >> LOG_R;

    // ------------------------------------------------------------------
    // Storage: input vector registers and weight memory
    // ------------------------------------------------------------------
    logic [7:0] xreg [N_MAX];

    // One register per element (a generate loop, so no simulator has to
    // unroll a large procedural loop of nonblocking array writes)
    for (genvar j = 0; j < N_MAX; j++) begin : g_xreg
        always_ff @(posedge clk) begin
            if (xb_valid && xb_ready)
                xreg[j] <= {7'd0, xb_bits[j]};
            else if (x_valid && x_ready && x_idx == AW'(j))
                xreg[j] <= x_data;
        end
    end

    logic [NB-1:0][LAW-1:0] wm_addr;
    logic [NB-1:0][7:0]     wm_data;

    weight_memory #(.N_MAX(N_MAX), .NB(NB)) u_wmem (
        .clk     (clk),
        .wr_en   (w_valid && w_ready),
        .wr_dst  (w_dst),
        .wr_src  (w_src),
        .wr_data (w_data),
        .rd_addr (wm_addr),
        .rd_data (wm_data)
    );

    // ------------------------------------------------------------------
    // Weight buffers: busy while a tile is loaded into / using the buffer
    // ------------------------------------------------------------------
    logic [WBUF-1:0] buf_busy;

    // ------------------------------------------------------------------
    // Loader
    // ------------------------------------------------------------------
    logic             ld_active;
    logic [LSW-1:0]   ld_step;
    logic [OGW-1:0]   ld_og;
    logic [IGW-1:0]   ld_ig;
    logic [SEL_W-1:0] ld_buf;
    logic [TW-1:0]    ld_started;   // tiles whose load has started
    logic [TW-1:0]    ld_done;      // tiles fully written into the array

    wire ld_start = (state == S_RUN) && !ld_active && (ld_started != total_q)
                    && !buf_busy[ld_buf];
    wire ld_issue = ld_start || ld_active;
    wire [LSW-1:0] cur_step = ld_active ? ld_step : '0;
    wire ld_last_step = (cur_step == LSW'(LSTEPS - 1));

    // Row/column addressed by this load step
    logic [RW-1:0] ld_r;
    logic [CW-1:0] ld_c;
    generate
        if (BANKED != 0) begin : g_ld_banked
            assign ld_r = RW'(cur_step);
            assign ld_c = '0;                 // all columns at once
        end else begin : g_ld_simple
            assign ld_r = RW'(cur_step >> LOG_C);
            assign ld_c = CW'(cur_step);      // cur_step % COLS
        end
    endgenerate

    // ld_ig * ROWS + ld_r and ld_og * COLS; always < N_MAX, one spare bit for compares
    wire [AW:0] ld_src  = ((AW+1)'(ld_ig) << LOG_R) + (AW+1)'(ld_r);
    wire [AW:0] ld_dst0 = (AW+1)'(ld_og) << LOG_C;

    // Per-bank read addresses and per-column validity masks
    logic [COLS-1:0] ld_mask;
    generate
        if (BANKED != 0) begin : g_addr_banked
            for (genvar b = 0; b < NB; b++) begin : g_b
                assign wm_addr[b] = LAW'({ld_og, ld_src[AW-1:0]});
                assign ld_mask[b] = ((ld_dst0 + b) < dim_q) && (ld_src < dim_q);
            end
        end else begin : g_addr_simple
            wire [AW:0] dst = ld_dst0 + (AW+1)'(ld_c);
            assign wm_addr[0] = LAW'({dst[AW-1:0], ld_src[AW-1:0]});
            for (genvar b = 0; b < COLS; b++) begin : g_m
                assign ld_mask[b] = (dst < dim_q) && (ld_src < dim_q);
            end
        end
    endgenerate

    // Load write stage (memory has one cycle of read latency)
    logic                   wl_v;
    logic                   wl_last;
    logic [RW-1:0]          wl_row;
    logic [COLS-1:0]        wl_colmask;
    logic [COLS-1:0]        wl_valmask;
    logic [SEL_W-1:0]       wl_sel;
    logic [COLS-1:0][7:0]   wl_data;

    always_ff @(posedge clk) begin
        wl_row  <= ld_r;
        wl_sel  <= ld_buf;
        wl_last <= ld_last_step;
        wl_valmask <= ld_mask;
        if (BANKED != 0)
            wl_colmask <= '1;
        else
            wl_colmask <= COLS'(1) << ld_c;
    end

    generate
        for (genvar c = 0; c < COLS; c++) begin : g_wl_data
            assign wl_data[c] = wl_valmask[c] ? wm_data[(BANKED != 0) ? c : 0] : 8'd0;
        end
    endgenerate

    // ------------------------------------------------------------------
    // Launcher
    // ------------------------------------------------------------------
    logic [TW-1:0]    lc_count;
    logic [OGW-1:0]   lc_og;
    logic [IGW-1:0]   lc_ig;
    logic [SEL_W-1:0] lc_buf;

    wire launch = (state == S_RUN) && (lc_count != ld_done);
    wire lc_first = (lc_ig == '0);
    wire lc_last  = ({1'b0, lc_ig} == nig_q - 1'b1);

    // Stage register at the array edge, then r extra cycles of skew per row
    logic                    ln_v;
    logic [ROWS-1:0][7:0]    ln_x;
    logic [SEL_W-1:0]        ln_sel;
    logic [TAG_W-1:0]        ln_tag;

    // x for row r of the launching tile. Rows beyond dim need no masking:
    // their weights were zeroed at load time, so they contribute exactly 0.
    logic [ROWS-1:0][7:0] lc_x;
    generate
        for (genvar r = 0; r < ROWS; r++) begin : g_lc_x
            wire [AW-1:0] src = AW'({lc_ig, {LOG_R{1'b0}}}) + AW'(r);
            assign lc_x[r] = xreg[src];
        end
    endgenerate

    always_ff @(posedge clk) begin
        ln_x   <= lc_x;
        ln_sel <= lc_buf;
        ln_tag <= {lc_og, lc_first, lc_last};
    end

    logic [ROWS-1:0][7:0]       x_row;
    logic [ROWS-1:0]            xv_row;
    logic [ROWS-1:0][SEL_W-1:0] xsel_row;
    logic [ROWS-1:0][TAG_W-1:0] xtag_row;

    generate
        for (genvar r = 0; r < ROWS; r++) begin : g_skew
            if (r == 0) begin : g_nodelay
                assign x_row[0]    = ln_x[0];
                assign xv_row[0]   = ln_v;
                assign xsel_row[0] = ln_sel;
                assign xtag_row[0] = ln_tag;
            end else begin : g_delay
                logic [7:0]       sx   [r];
                logic             sv   [r];
                logic [SEL_W-1:0] ssel [r];
                logic [TAG_W-1:0] stag [r];
                always_ff @(posedge clk) begin
                    sx[0]   <= ln_x[r];
                    ssel[0] <= ln_sel;
                    stag[0] <= ln_tag;
                    for (int k = 1; k < r; k++) begin
                        sx[k]   <= sx[k-1];
                        ssel[k] <= ssel[k-1];
                        stag[k] <= stag[k-1];
                    end
                end
                always_ff @(posedge clk) begin
                    if (rst) begin
                        for (int k = 0; k < r; k++) sv[k] <= 1'b0;
                    end else begin
                        sv[0] <= ln_v;
                        for (int k = 1; k < r; k++) sv[k] <= sv[k-1];
                    end
                end
                assign x_row[r]    = sx[r-1];
                assign xv_row[r]   = sv[r-1];
                assign xsel_row[r] = ssel[r-1];
                assign xtag_row[r] = stag[r-1];
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // Array
    // ------------------------------------------------------------------
    logic [COLS-1:0][31:0]      ps_col;
    logic [COLS-1:0]            pv_col;
    logic [COLS-1:0][TAG_W-1:0] ptag_col;

    systolic_array #(
        .ROWS(ROWS), .COLS(COLS), .WBUF(WBUF), .SEL_W(SEL_W), .TAG_W(TAG_W)
    ) u_array (
        .clk        (clk),
        .rst        (rst),
        .wl_en      (wl_v),
        .wl_row     (wl_row),
        .wl_colmask (wl_colmask),
        .wl_sel     (wl_sel),
        .wl_data    (wl_data),
        .x_row      (x_row),
        .xv_row     (xv_row),
        .xsel_row   (xsel_row),
        .xtag_row   (xtag_row),
        .ps_col     (ps_col),
        .pv_col     (pv_col),
        .ptag_col   (ptag_col)
    );

    // ------------------------------------------------------------------
    // Collector and result buffer (one bank per column: dst % COLS == c)
    // ------------------------------------------------------------------
    logic [TW-1:0]    fin_count;
    logic [SEL_W-1:0] fin_buf;
    wire              tile_fin = pv_col[COLS-1];

    logic [COLS-1:0][31:0] rb_rd;     // per-bank read data for the drain index
    logic [AW:0] out_idx;

    generate
        for (genvar c = 0; c < COLS; c++) begin : g_collect
            logic [31:0] rbank [NOG_MAX];
            logic [31:0] col_acc;
            wire [OGW-1:0] og    = ptag_col[c][TAG_W-1:2];
            wire           first = ptag_col[c][1];
            wire           last  = ptag_col[c][0];
            wire [31:0]    sum   = first ? ps_col[c] : (col_acc + ps_col[c]);
            wire [AW:0]    dst   = ((AW+1)'(og) << LOG_C) + (AW+1)'(c);

            always_ff @(posedge clk) begin
                if (pv_col[c]) begin
                    col_acc <= sum;
                    if (last && (dst < dim_q))
                        rbank[og] <= sum;
                end
            end

            // Drain read: result out_idx lives in bank out_idx % COLS,
            // entry out_idx / COLS. Not written during DRAIN, so it is stable.
            assign rb_rd[c] = rbank[OGW'(out_idx >> LOG_C)];
        end
    endgenerate

    // ------------------------------------------------------------------
    // Result stream
    // ------------------------------------------------------------------
    wire  [AW:0] dim_m1 = dim_q - 1'b1;

    generate
        if (COLS == 1) begin : g_rd1
            assign res_data = rb_rd[0];
        end else begin : g_rdn
            assign res_data = rb_rd[out_idx[CW-1:0]];
        end
    endgenerate

    assign res_valid = (state == S_DRAIN);
    assign res_idx   = out_idx[AW-1:0];
    assign res_last  = (out_idx == dim_m1);

    // ------------------------------------------------------------------
    // Control state
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            done       <= 1'b0;
            err_dim    <= 1'b0;
            ld_active  <= 1'b0;
            wl_v       <= 1'b0;
            ln_v       <= 1'b0;
            buf_busy   <= '0;
            out_idx    <= '0;
        end else begin
            done    <= 1'b0;
            err_dim <= 1'b0;

            // defaults for single-cycle strobes
            wl_v <= ld_issue;
            ln_v <= launch;

            // ---------------- loader ----------------
            if (ld_issue) begin
                if (ld_last_step) begin
                    ld_active  <= 1'b0;
                    ld_step    <= '0;
                    ld_started <= ld_started + 1'b1;
                    ld_buf     <= (ld_buf == SEL_W'(WBUF - 1)) ? '0 : ld_buf + 1'b1;
                    if ({1'b0, ld_ig} == nig_q - 1'b1) begin
                        ld_ig <= '0;
                        ld_og <= ld_og + 1'b1;
                    end else begin
                        ld_ig <= ld_ig + 1'b1;
                    end
                end else begin
                    ld_active <= 1'b1;
                    ld_step   <= cur_step + 1'b1;
                end
            end
            if (wl_v && wl_last)
                ld_done <= ld_done + 1'b1;

            // ---------------- launcher ----------------
            if (launch) begin
                lc_count <= lc_count + 1'b1;
                lc_buf   <= (lc_buf == SEL_W'(WBUF - 1)) ? '0 : lc_buf + 1'b1;
                if (lc_last) begin
                    lc_ig <= '0;
                    lc_og <= lc_og + 1'b1;
                end else begin
                    lc_ig <= lc_ig + 1'b1;
                end
            end

            // ---------------- buffer bookkeeping ----------------
            for (int b = 0; b < WBUF; b++) begin
                if (ld_start && ld_buf == SEL_W'(b))
                    buf_busy[b] <= 1'b1;
                else if (tile_fin && fin_buf == SEL_W'(b))
                    buf_busy[b] <= 1'b0;
            end
            if (tile_fin) begin
                fin_count <= fin_count + 1'b1;
                fin_buf   <= (fin_buf == SEL_W'(WBUF - 1)) ? '0 : fin_buf + 1'b1;
            end

            // ---------------- operation state ----------------
            case (state)
                S_IDLE: if (cmd_fire) begin
                    if (dim_ok) begin
                        dim_q      <= cmd_dim;
                        nig_q      <= (IGW+1)'(nig_calc);
                        total_q    <= TW'(nog_calc * nig_calc);
                        ld_active  <= 1'b0;
                        ld_step    <= '0;
                        ld_og      <= '0;
                        ld_ig      <= '0;
                        ld_buf     <= '0;
                        ld_started <= '0;
                        ld_done    <= '0;
                        lc_count   <= '0;
                        lc_og      <= '0;
                        lc_ig      <= '0;
                        lc_buf     <= '0;
                        fin_count  <= '0;
                        fin_buf    <= '0;
                        buf_busy   <= '0;
                        state      <= S_RUN;
                    end else begin
                        done    <= 1'b1;
                        err_dim <= 1'b1;
                    end
                end
                S_RUN: if (tile_fin && (fin_count + 1'b1 == total_q)) begin
                    out_idx <= '0;
                    state   <= S_DRAIN;
                end
                S_DRAIN: if (res_ready) begin
                    if (res_last) begin
                        state <= S_IDLE;
                        done  <= 1'b1;
                    end else begin
                        out_idx <= out_idx + 1'b1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
