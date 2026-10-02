// systolic_array.sv
// ROWS x COLS grid of systolic_pe.
//
//   PE[r][c] holds W[out_base + c][in_base + r] for the current tile.
//   Row r receives x[in_base + r] (already skewed by r cycles by the caller).
//   Row 0 receives psum = 0 and takes its psum tag from the x path.
//   Column c's finished dot-product piece leaves the bottom of the column.
//
// Timing (launch = cycle L at the array's left edge, row r enters at L + r):
//   PE[r][c] computes in cycle L + r + c, registering at the end of it.
//   Column c output is valid (bottom registers) in cycle L + ROWS + c.

`timescale 1ns/1ps

module systolic_array #(
    parameter int ROWS  = 4,
    parameter int COLS  = 4,
    parameter int WBUF  = 2,
    parameter int SEL_W = (WBUF <= 1) ? 1 : $clog2(WBUF),
    parameter int TAG_W = 8,
    parameter int RW    = (ROWS <= 1) ? 1 : $clog2(ROWS)
) (
    input  logic                         clk,
    input  logic                         rst,

    // weight load: writes row wl_row, columns selected by wl_colmask
    input  logic                         wl_en,
    input  logic [RW-1:0]                wl_row,
    input  logic [COLS-1:0]              wl_colmask,
    input  logic [SEL_W-1:0]             wl_sel,
    input  logic [COLS-1:0][7:0]         wl_data,

    // skewed row inputs
    input  logic [ROWS-1:0][7:0]         x_row,
    input  logic [ROWS-1:0]              xv_row,
    input  logic [ROWS-1:0][SEL_W-1:0]   xsel_row,
    input  logic [ROWS-1:0][TAG_W-1:0]   xtag_row,

    // column outputs
    output logic [COLS-1:0][31:0]        ps_col,
    output logic [COLS-1:0]              pv_col,
    output logic [COLS-1:0][TAG_W-1:0]   ptag_col
);

    // Inter-PE wires. h*[r][c] is the input to PE[r][c] from the left;
    // v*[r][c] is the input to PE[r][c] from above.
    logic [7:0]       hx   [ROWS][COLS+1];
    logic             hv   [ROWS][COLS+1];
    logic [SEL_W-1:0] hsel [ROWS][COLS+1];
    logic [TAG_W-1:0] htag [ROWS][COLS+1];
    logic [31:0]      vps  [ROWS+1][COLS];
    logic             vpv  [ROWS+1][COLS];
    logic [TAG_W-1:0] vtag [ROWS+1][COLS];

    // Flattened per-PE input valid bits, for assertions only (no logic uses them)
    logic [ROWS*COLS-1:0] dbg_xv_in, dbg_pv_in;

    genvar r, c;
    generate
        for (r = 0; r < ROWS; r++) begin : g_row_in
            assign hx[r][0]   = x_row[r];
            assign hv[r][0]   = xv_row[r];
            assign hsel[r][0] = xsel_row[r];
            assign htag[r][0] = xtag_row[r];
        end

        for (r = 0; r < ROWS; r++) begin : g_r
            for (c = 0; c < COLS; c++) begin : g_c
                // Row 0: synthetic partial-sum input aligned with the x wavefront
                logic [31:0]      ps_in;
                logic             pv_in;
                logic [TAG_W-1:0] ptag_in;
                if (r == 0) begin : g_top
                    assign ps_in   = 32'd0;
                    assign pv_in   = hv[0][c];
                    assign ptag_in = htag[0][c];
                end else begin : g_mid
                    assign ps_in   = vps[r][c];
                    assign pv_in   = vpv[r][c];
                    assign ptag_in = vtag[r][c];
                end

                assign dbg_xv_in[r*COLS + c] = hv[r][c];
                assign dbg_pv_in[r*COLS + c] = pv_in;

                systolic_pe #(.WBUF(WBUF), .SEL_W(SEL_W), .TAG_W(TAG_W)) u_pe (
                    .clk      (clk),
                    .rst      (rst),
                    .wl_en    (wl_en && (wl_row == RW'(r)) && wl_colmask[c]),
                    .wl_sel   (wl_sel),
                    .wl_data  (wl_data[c]),
                    .x_in     (hx[r][c]),
                    .xv_in    (hv[r][c]),
                    .xsel_in  (hsel[r][c]),
                    .xtag_in  (htag[r][c]),
                    .x_out    (hx[r][c+1]),
                    .xv_out   (hv[r][c+1]),
                    .xsel_out (hsel[r][c+1]),
                    .xtag_out (htag[r][c+1]),
                    .ps_in    (ps_in),
                    .pv_in    (pv_in),
                    .ptag_in  (ptag_in),
                    .ps_out   (vps[r+1][c]),
                    .pv_out   (vpv[r+1][c]),
                    .ptag_out (vtag[r+1][c])
                );
            end
        end

        for (c = 0; c < COLS; c++) begin : g_col_out
            assign ps_col[c]   = vps[ROWS][c];
            assign pv_col[c]   = vpv[ROWS][c];
            assign ptag_col[c] = vtag[ROWS][c];
        end
    endgenerate

endmodule
