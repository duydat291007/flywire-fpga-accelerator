// input_conditioner.sv
// For one asynchronous board input (button or switch):
//   1. two-flop synchronizer (reduces metastability risk; it is not a proof
//      that metastability cannot propagate)
//   2. debounce: the synchronized value must stay stable for DEBOUNCE cycles
//      before the filtered level changes
//   3. rise: one-cycle pulse when the filtered level goes 0 -> 1
//
// INIT is the filtered level after reset (0 for buttons and switches).

`timescale 1ns/1ps

module input_conditioner #(
    parameter int   DEBOUNCE = 1_000_000,     // 10 ms at 100 MHz
    parameter logic INIT     = 1'b0
) (
    input  logic clk,
    input  logic rst,
    input  logic async_in,
    output logic level,
    output logic rise
);
    localparam int CW = (DEBOUNCE <= 1) ? 1 : $clog2(DEBOUNCE + 1);

    (* ASYNC_REG = "TRUE" *) logic s1, s2;
    logic [CW-1:0] cnt;

    always_ff @(posedge clk) begin
        s1 <= async_in;
        s2 <= s1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            level <= INIT;
            cnt   <= '0;
            rise  <= 1'b0;
        end else begin
            rise <= 1'b0;
            if (s2 == level) begin
                cnt <= '0;
            end else if (cnt == CW'(DEBOUNCE - 1)) begin
                level <= s2;
                rise  <= s2;
                cnt   <= '0;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end
endmodule
