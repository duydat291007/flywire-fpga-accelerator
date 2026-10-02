// tb_uart_tx.sv
// Cycle-exact check of the 8N1 transmitter: every bit must hold its value
// for exactly DIV cycles; start = 0, data LSB first, stop = 1; back-to-back
// bytes leave no idle gap; reset mid-byte returns the line to idle at once.

`timescale 1ns/1ps

module tb_uart_tx #(parameter int DIV = 16, parameter int NBYTES = 200);
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic in_valid = 0, in_ready, txd;
    logic [7:0] in_data = 0;

    uart_tx #(.DIV(DIV)) dut (.*);

    task automatic tick(); @(posedge clk); #1; endtask

    // Expect one frame starting at the current cycle (txd just went low).
    task automatic expect_frame(input logic [7:0] b);
        logic [9:0] frame;
        frame = {1'b1, b, 1'b0};
        for (int k = 0; k < 10; k++)
            for (int c = 0; c < DIV; c++) begin
                if (txd !== frame[k])
                    $fatal(1, "byte %02h bit %0d cycle %0d: txd=%b expected %b", b, k, c, txd, frame[k]);
                tick();
            end
    endtask

    initial begin
        int unsigned lcg = 7;
        logic [7:0] data [NBYTES];
        repeat (3) tick();
        rst = 0;
        tick();
        if (txd !== 1'b1 || !in_ready) $fatal(1, "not idle after reset");

        for (int i = 0; i < NBYTES; i++) begin
            lcg = lcg * 1103515245 + 12345;
            data[i] = (i < 4) ? (8'h00 | (i == 1 ? 8'hFF : 0) | (i == 2 ? 8'hA5 : 0) | (i == 3 ? 8'h5A : 0))
                              : 8'(lcg >> 16);
        end

        // Back-to-back stream: in_valid held high the whole time
        for (int i = 0; i < NBYTES; i++) begin
            in_valid = 1; in_data = data[i];
            @(posedge clk);
            if (!in_ready) $fatal(1, "not ready for byte %0d", i);
            #1;
            in_valid = (i + 1 < NBYTES);
            if (i + 1 < NBYTES) in_data = data[i + 1];
            expect_frame(data[i]);
            if (!in_ready && i + 1 < NBYTES) $fatal(1, "gap/ready error after byte %0d", i);
        end
        in_valid = 0;
        repeat (3 * DIV) begin
            tick();
            if (txd !== 1'b1) $fatal(1, "line not idle after stream");
        end

        // Reset in the middle of a byte
        in_valid = 1; in_data = 8'h00;
        tick();
        in_valid = 0;
        repeat (3 * DIV + 2) tick();
        rst = 1; tick(); rst = 0;
        if (txd !== 1'b1 || !in_ready) $fatal(1, "reset mid-byte did not idle the line");

        $display("PASS tb_uart_tx: %0d bytes, DIV=%0d, cycle-exact framing", NBYTES, DIV);
        $finish;
    end
endmodule
