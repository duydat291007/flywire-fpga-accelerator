// lif_update.sv
// Combinational leaky integrate-and-fire update for one neuron. Bit-accurate
// with model/fly_model/reference.py:lif_update.
//
//   leaked    = (15 * V) >> 4                      unsigned, 20-bit product
//   candidate = leaked + I + U                     signed 34-bit, no overflow
//   spike     = candidate >= THRESHOLD
//   V_next    = spike ? 0 : (candidate < 0 ? 0 : candidate[15:0])
//
// Width argument: leaked <= 65535 (17 bits signed), I is signed 32, U <= 255.
// |candidate| < 2^31 + 2^16 + 2^8 < 2^33, so signed 34 bits always suffice.
// When no spike occurs candidate < THRESHOLD <= 65535, so candidate[15:0] is exact.

`timescale 1ns/1ps

module lif_update #(
    parameter int THRESHOLD = 100
) (
    input  logic [15:0] v,          // stored potential, 0 <= v < THRESHOLD
    input  logic [31:0] i_in,       // network input, signed
    input  logic [7:0]  u_in,       // external input, unsigned
    output logic [15:0] v_next,
    output logic        spike
);
    initial if (THRESHOLD < 1 || THRESHOLD > 65535)
        $fatal(1, "THRESHOLD must be 1..65535");

    wire        [19:0] v15      = 20'(v) * 20'd15;
    wire        [15:0] leaked   = 16'(v15 >> 4);          // floor(15*V/16) <= V: no bits lost
    wire signed [33:0] cand     = $signed({18'd0, leaked})
                                + $signed({{2{i_in[31]}}, i_in})
                                + $signed({26'd0, u_in});

    assign spike  = (cand >= $signed(34'(THRESHOLD)));
    assign v_next = (spike || cand[33]) ? 16'd0 : cand[15:0];
endmodule
