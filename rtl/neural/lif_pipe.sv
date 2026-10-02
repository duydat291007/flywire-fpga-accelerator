// lif_pipe.sv
// Pipelined form of lif_update (same arithmetic, bit-exact), used by fly_core
// to meet 100 MHz. lif_update.sv stays as the single-cycle reference and both
// are checked against the same model vectors in tb_lif.
//
//   in_*  registered (stage 1)
//   cand = leaked + I + U registered (stage 2)
//   out_* combinational from stage 2: spike = cand >= THRESHOLD, v_next
//
// Latency: outputs for an input accepted at edge k are valid after edge k+2.
// One input per cycle, no stalls. The tag travels with the data.

`timescale 1ns/1ps

module lif_pipe #(
    parameter int THRESHOLD = 100,
    parameter int TAG_W     = 7
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             in_valid,
    input  logic [15:0]      in_v,
    input  logic [31:0]      in_i,
    input  logic [7:0]       in_u,
    input  logic [TAG_W-1:0] in_tag,
    output logic             out_valid,
    output logic [15:0]      out_v_next,
    output logic             out_spike,
    output logic [TAG_W-1:0] out_tag
);
    initial if (THRESHOLD < 1 || THRESHOLD > 65535)
        $fatal(1, "THRESHOLD must be 1..65535");

    // ---- stage 1: capture ----
    logic             s1_valid;
    logic [15:0]      s1_v;
    logic [31:0]      s1_i;
    logic [7:0]       s1_u;
    logic [TAG_W-1:0] s1_tag;

    // ---- stage 2: candidate ----
    logic             s2_valid;
    logic signed [33:0] s2_cand;
    logic [TAG_W-1:0] s2_tag;

    wire        [19:0] v15    = 20'(s1_v) * 20'd15;
    wire        [15:0] leaked = 16'(v15 >> 4);                 // floor(15*V/16) <= V
    wire signed [33:0] cand   = $signed({18'd0, leaked})
                              + $signed({{2{s1_i[31]}}, s1_i})
                              + $signed({26'd0, s1_u});

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
        end else begin
            s1_valid <= in_valid;
            s2_valid <= s1_valid;
        end
    end

    always_ff @(posedge clk) begin
        s1_v    <= in_v;
        s1_i    <= in_i;
        s1_u    <= in_u;
        s1_tag  <= in_tag;
        s2_cand <= cand;
        s2_tag  <= s1_tag;
    end

    assign out_valid  = s2_valid;
    assign out_tag    = s2_tag;
    assign out_spike  = (s2_cand >= $signed(34'(THRESHOLD)));
    assign out_v_next = (out_spike || s2_cand[33]) ? 16'd0 : s2_cand[15:0];
endmodule
