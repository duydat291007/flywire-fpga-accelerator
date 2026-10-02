// tb_basys3_top.sv
// Board-level smoke test with shortened timing parameters:
//   - power-on reset, boot, LED[5] (booted)
//   - pause mode: a bouncing btnU press produces exactly one timestep
//   - run mode: timesteps advance at the pacing period
//   - food switch on: final state printed for an exact model comparison
//   - btnC reset mid-run returns step count to 0 and reboots
//   - the UART stream is captured to BYTES_OUT for tests/check_stream.py

`timescale 1ns/1ps

module tb_basys3_top #(
    parameter ROM_PATH  = "rtl/common/network_weights.mem",
    parameter BYTES_OUT = "build/top_bytes.txt"
);
    localparam int DIV = 4, DEB = 8, STEP = 40000, TELEM = 20000;
    localparam int BOOT = 70000;    // 65536 weight writes + margin

    logic clk = 0;
    always #5 clk = ~clk;
    logic btnC = 0, btnU = 0, btnL = 0, btnR = 0;
    logic [15:0] sw = 0;
    logic [15:0] led;
    logic RsTx;

    basys3_top #(.ROM_FILE(ROM_PATH), .DEBOUNCE(DEB), .STEP_PERIOD(STEP), .SLOW_PERIOD(4 * STEP),
                 .TELEM_PERIOD(TELEM), .UART_DIV(DIV), .POR_CYCLES(20)) dut (.*);

    task automatic wait_cycles(input int n); repeat (n) @(posedge clk); #1; endtask
    function automatic int steps(); return int'(dut.step_count); endfunction

    // UART receiver -> file
    int fo, nbytes = 0;
    always begin
        logic [7:0] b;
        @(negedge RsTx);
        repeat (DIV / 2) @(posedge clk);
        if (RsTx === 1'b0) begin
            for (int k = 0; k < 8; k++) begin repeat (DIV) @(posedge clk); b[k] = RsTx; end
            repeat (DIV) @(posedge clk);
            if (RsTx !== 1'b1) $fatal(1, "UART framing error");
            $fwrite(fo, "%02x\n", b);
            nbytes++;
        end
    end

    // A mechanical press: a burst of bounces, a stable hold, bouncing release
    task automatic bounce_press(ref logic btn);
        for (int i = 0; i < 5; i++) begin btn = 1; wait_cycles(2); btn = 0; wait_cycles(3); end
        btn = 1; wait_cycles(10 * DEB);
        for (int i = 0; i < 4; i++) begin btn = 0; wait_cycles(2); btn = 1; wait_cycles(2); end
        btn = 0; wait_cycles(10 * DEB);
    endtask

    initial begin
        int s0;
        fo = $fopen(BYTES_OUT, "w");

        // Power-on reset and boot (65536 weight writes)
        wait_cycles(BOOT);
        if (!led[5]) $fatal(1, "not booted after power-on");
        if (steps() != 0) $fatal(1, "steps advanced while paused");

        // Pause mode: each bouncing press = exactly one step
        for (int i = 1; i <= 3; i++) begin
            bounce_press(btnU);
            wait_cycles(STEP);
            if (steps() != i) $fatal(1, "single step: expected %0d steps, got %0d", i, steps());
        end

        // Run mode with food present
        sw[1] = 1;  // food
        sw[0] = 1;  // run
        wait_cycles(20 * DEB);
        s0 = steps();
        wait_cycles(60 * STEP);
        if (steps() - s0 < 55) $fatal(1, "run mode too slow: %0d steps", steps() - s0);
        // Exact state is checked against the model by tests/check_top_state.py
        // (3 paused steps without food, then food on for every later step).
        if (!led[1] || !led[2]) $fatal(1, "run/food LEDs wrong");

        // Pause again: steps stop
        sw[0] = 0;
        wait_cycles(20 * DEB + STEP);
        s0 = steps();
        wait_cycles(10 * STEP);
        if (steps() != s0) $fatal(1, "steps advanced while paused");
        $display("STATE step=%0d fly=%0d,%0d heading=%0d food=%0d,%0d eaten=%0d lfsr=%0d",
                 steps(), dut.fly_x, dut.fly_y, dut.heading, dut.food_x, dut.food_y, dut.eaten, dut.lfsr);

        // Reset button
        bounce_press(btnC);
        wait_cycles(20);
        if (steps() != 0) $fatal(1, "reset button did not clear step count");
        wait_cycles(BOOT);
        if (!led[5]) $fatal(1, "not rebooted after reset");

        wait_cycles(2 * TELEM + 130 * 10 * DIV);
        $fclose(fo);
        $display("PASS tb_basys3_top: boot, bouncing single-step, run/pause, food present, reset; %0d UART bytes",
                 nbytes);
        $finish;
    end
endmodule
