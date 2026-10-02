// systolic_pe.sv
// Weight-stationary processing element.
//
//   x   moves left -> right (registered), with its valid bit, weight-buffer
//       select (xsel) and tile tag.
//   psum moves top -> bottom (registered), with its valid bit and tag.
//
//   psum_out <= psum_in + sext32(wbuf[xsel_in] * x_in)      when x_valid
//
// WBUF weight registers per PE let the controller load the next tile's
// weights while the current tile's wavefront is still in flight. Which buffer
// a wavefront uses travels with the data (xsel), so the swap happens exactly
// when the wavefront reaches each PE - no global swap signal.

`timescale 1ns/1ps

// use_dsp: map the multiply-add to a DSP48E1 (Vivado otherwise built
// these 8x8 multipliers from LUTs: methodology warning SYNTH-9).
(* use_dsp = "yes" *)
module systolic_pe #(
    parameter int WBUF  = 2,
    parameter int SEL_W = (WBUF <= 1) ? 1 : $clog2(WBUF),
    parameter int TAG_W = 8
) (
    input  logic                    clk,
    input  logic                    rst,

    // weight load
    input  logic                    wl_en,
    input  logic [SEL_W-1:0]        wl_sel,
    input  logic [7:0]              wl_data,

    // horizontal (input) path
    input  logic [7:0]              x_in,
    input  logic                    xv_in,
    input  logic [SEL_W-1:0]        xsel_in,
    input  logic [TAG_W-1:0]        xtag_in,
    output logic [7:0]              x_out,
    output logic                    xv_out,
    output logic [SEL_W-1:0]        xsel_out,
    output logic [TAG_W-1:0]        xtag_out,

    // vertical (partial-sum) path
    input  logic [31:0]             ps_in,
    input  logic                    pv_in,
    input  logic [TAG_W-1:0]        ptag_in,
    output logic [31:0]             ps_out,
    output logic                    pv_out,
    output logic [TAG_W-1:0]        ptag_out
);

    logic [7:0] wbuf [WBUF];

    always_ff @(posedge clk)
        if (wl_en)
            wbuf[wl_sel] <= wl_data;

    wire signed [15:0] prod     = $signed(wbuf[xsel_in]) * $signed(x_in);
    wire signed [31:0] prod_ext = 32'(prod);

    // valid bits: reset clears them (abort)
    always_ff @(posedge clk) begin
        if (rst) begin
            xv_out <= 1'b0;
            pv_out <= 1'b0;
        end else begin
            xv_out <= xv_in;
            pv_out <= pv_in && xv_in;
        end
    end

    // data and metadata: no reset, qualified by the valid bits
    always_ff @(posedge clk) begin
        x_out    <= x_in;
        xsel_out <= xsel_in;
        xtag_out <= xtag_in;
        ps_out   <= $signed(ps_in) + prod_ext;
        ptag_out <= ptag_in;
    end

endmodule
