// mvu_serial.sv
// Serial matrix-vector baseline: one signed 8x8 multiply-accumulate per clock.
// Port-compatible with mvu_systolic. Behavior is specified in
// docs/specification.md section 2.
//
// Schedule for dim = n:
//   cycle 0          : command accepted (IDLE)
//   cycles 1..n*n    : one weight read per cycle, i-major (dst), j-minor (src)
//   +1 cycle         : last product lands in result buffer (memory read latency)
//   DRAIN            : results offered in order 0..n-1 on res_* (valid/ready)

`timescale 1ns/1ps

// use_dsp: map the multiply-add to a DSP48E1 (Vivado otherwise built
// these 8x8 multipliers from LUTs: methodology warning SYNTH-9).
(* use_dsp = "yes" *)
module mvu_serial #(
    parameter int N_MAX = 64
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

    localparam int AW = $clog2(N_MAX);
    localparam int DW = AW + 1;

    typedef enum logic [1:0] {S_IDLE, S_RUN, S_FLUSH, S_DRAIN} state_t;
    state_t state;

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------
    logic [7:0]  wmem [N_MAX*N_MAX];   // W[dst][src] at dst*N_MAX + src
    logic [7:0]  xreg [N_MAX];
    logic [31:0] rbuf [N_MAX];

    logic [DW-1:0] dim_q;

    assign busy      = (state != S_IDLE);
    assign cmd_ready = !busy;
    assign w_ready   = !busy;
    assign x_ready   = !busy;
    assign xb_ready  = !busy;

    wire cmd_fire = cmd_valid && cmd_ready;
    wire dim_ok   = (cmd_dim != '0) && (cmd_dim <= DW'(N_MAX));

    // ------------------------------------------------------------------
    // Weight memory: synchronous write (idle only) and synchronous read.
    // ------------------------------------------------------------------
    logic [AW-1:0] rd_i, rd_j;
    logic [7:0]    w_rd;

    always_ff @(posedge clk) begin
        if (w_valid && w_ready)
            wmem[{w_dst, w_src}] <= w_data;
        w_rd <= wmem[{rd_i, rd_j}];
    end

    // Input vector registers
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

    // ------------------------------------------------------------------
    // Issue and MAC pipeline
    //   stage 0 (RUN): address (rd_i, rd_j) issued
    //   stage 1      : w_rd valid; multiply by xreg[j1]; accumulate
    // ------------------------------------------------------------------
    logic          v1, first1, last1;
    logic [AW-1:0] i1, j1;
    logic signed [31:0] acc;

    wire [AW:0] dim_m1 = dim_q - 1'b1;
    wire issue      = (state == S_RUN);
    wire issue_last_j = (rd_j == dim_m1[AW-1:0]);
    wire issue_last_i = (rd_i == dim_m1[AW-1:0]);

    wire signed [15:0] prod     = $signed(w_rd) * $signed(xreg[j1]);
    wire signed [31:0] prod_ext = 32'(prod);                 // sign-extending cast
    wire signed [31:0] acc_next = (first1 ? 32'sd0 : acc) + prod_ext;

    logic [AW:0] out_idx;   // one extra bit so the "last" compare is simple

    // Datapath registers: no reset needed (qualified by v1), which keeps the
    // result buffer inferable as distributed RAM.
    always_ff @(posedge clk) begin
        i1     <= rd_i;
        j1     <= rd_j;
        first1 <= (rd_j == '0);
        last1  <= issue_last_j;
        if (v1) begin
            acc <= acc_next;
            if (last1)
                rbuf[i1] <= acc_next;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            v1      <= 1'b0;
            done    <= 1'b0;
            err_dim <= 1'b0;
            rd_i    <= '0;
            rd_j    <= '0;
            out_idx <= '0;
        end else begin
            done    <= 1'b0;
            err_dim <= 1'b0;

            v1 <= issue;

            case (state)
                S_IDLE: if (cmd_fire) begin
                    if (dim_ok) begin
                        dim_q <= cmd_dim;
                        rd_i  <= '0;
                        rd_j  <= '0;
                        state <= S_RUN;
                    end else begin
                        done    <= 1'b1;
                        err_dim <= 1'b1;
                    end
                end
                S_RUN: begin
                    if (issue_last_j) begin
                        rd_j <= '0;
                        rd_i <= rd_i + 1'b1;
                        if (issue_last_i)
                            state <= S_FLUSH;
                    end else begin
                        rd_j <= rd_j + 1'b1;
                    end
                end
                S_FLUSH: begin          // last product is being accumulated this cycle
                    if (!v1) begin
                        out_idx <= '0;
                        state   <= S_DRAIN;
                    end
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

    // ------------------------------------------------------------------
    // Result stream (data comes straight from the result buffer, which is
    // not written during DRAIN, so it is stable under backpressure)
    // ------------------------------------------------------------------
    assign res_valid = (state == S_DRAIN);
    assign res_idx   = out_idx[AW-1:0];
    assign res_data  = rbuf[out_idx[AW-1:0]];
    assign res_last  = (out_idx == dim_m1);

endmodule
