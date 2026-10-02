// uart_tx.sv
// 8N1 UART transmitter: idle high, start bit 0, 8 data bits LSB first, stop
// bit 1. One byte per valid/ready handshake. Bit time = DIV clock cycles
// (100 MHz / 868 = 115,207 baud for the default).
//
// Reset returns the line to idle (high) immediately, abandoning any byte.

`timescale 1ns/1ps

module uart_tx #(
    parameter int DIV = 868
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       in_valid,
    output logic       in_ready,
    input  logic [7:0] in_data,
    output logic       txd
);
    localparam int DW = $clog2(DIV);

    logic [9:0]    shreg;        // {stop, data[7:0], start}, shifted out LSB first
    logic [3:0]    bits_left;
    logic [DW-1:0] baud_cnt;

    assign in_ready = (bits_left == 0);

    always_ff @(posedge clk) begin
        if (rst) begin
            txd       <= 1'b1;
            bits_left <= '0;
            baud_cnt  <= '0;
            shreg     <= '1;
        end else if (in_valid && in_ready) begin
            shreg     <= {1'b1, in_data, 1'b0};
            txd       <= 1'b0;                  // start bit begins now
            bits_left <= 4'd10;
            baud_cnt  <= DW'(DIV - 1);
        end else if (bits_left != 0) begin
            if (baud_cnt == 0) begin
                baud_cnt  <= DW'(DIV - 1);
                bits_left <= bits_left - 1'b1;
                shreg     <= {1'b1, shreg[9:1]};
                txd       <= (bits_left == 4'd1) ? 1'b1 : shreg[1];
            end else begin
                baud_cnt <= baud_cnt - 1'b1;
            end
        end
    end
endmodule
