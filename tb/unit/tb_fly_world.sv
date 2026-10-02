// tb_fly_world.sv
// World-only test: fly_world driven with random output-neuron spikes and
// random switch/button activity from tests/vectors/world_vectors.txt
// (model/gen_world_vectors.py). Before every update it checks the four sensor
// drives; after every update it checks the complete world state against the
// Python World model. Random spikes reach world rules that the closed-loop
// trace rarely hits (catches by pursuit, jumps into corners, backing up).

`timescale 1ns/1ps

module tb_fly_world #(
    parameter VECTORS = "tests/vectors/world_vectors.txt"
);
    import fly_cfg_pkg::*;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic food_present = 0, threat_present = 0, rf_evt = 0, rt_evt = 0, update = 0, done;
    logic [N_NEURONS-1:0] spikes = '0;
    logic [3:0][7:0] u_sens;
    logic [5:0] fly_x, fly_y, food_x, food_y, threat_x, threat_y;
    logic [2:0] heading, last_action;
    logic [15:0] eaten, caught, jumps, lfsr;
    logic [5:0][7:0] last_motor;

    fly_world dut (
        .clk, .rst, .food_present, .threat_present,
        .respawn_food_evt(rf_evt), .respawn_threat_evt(rt_evt),
        .update, .done, .spikes, .u_sens,
        .fly_x, .fly_y, .food_x, .food_y, .threat_x, .threat_y, .heading,
        .eaten, .caught, .jumps, .lfsr, .last_action, .last_motor);

    task automatic tick(); @(posedge clk); #1; endtask

    initial begin
        int fd, r, n, f, th, rf, rt, tmp, cyc;
        int u [4];
        int e [13];        // lfsr fx fy h gx gy tx ty eaten caught jumps action window_count
        int m [6];
        logic [23:0] outb;
        int checked_catch_window, prev_caught;
        checked_catch_window = 0;
        prev_caught = 0;

        fd = $fopen(VECTORS, "r");
        if (fd == 0) $fatal(1, "cannot open %s", VECTORS);
        r = $fscanf(fd, "%d", n);
        repeat (3) tick();
        rst = 0;
        tick();

        for (int s = 0; s < n; s++) begin
            r = $fscanf(fd, "%d %d %d %d %h", f, th, rf, rt, outb);
            for (int k = 0; k < 4; k++) begin r = $fscanf(fd, "%d", tmp); u[k] = tmp; end
            for (int k = 0; k < 13; k++) begin r = $fscanf(fd, "%d", tmp); e[k] = tmp; end
            for (int k = 0; k < 6; k++) begin r = $fscanf(fd, "%d", tmp); m[k] = tmp; end

            food_present = f[0]; threat_present = th[0];
            if (rf || rt) begin
                rf_evt = rf[0]; rt_evt = rt[0];
                tick();
                rf_evt = 0; rt_evt = 0;
            end
            #1;
            for (int k = 0; k < 4; k++)
                if (u_sens[k] !== 8'(u[k])) begin
                    $display("FAIL step %0d: sensor %0d rtl=%0d model=%0d (fly %0d,%0d h=%0d)",
                             s + 1, k, u_sens[k], u[k], fly_x, fly_y, heading);
                    $fatal(1, "sensor mismatch");
                end

            spikes = '0;
            spikes[255:232] = outb;
            update = 1;
            tick();
            update = 0;
            cyc = 0;
            while (!done) begin
                tick();
                if (++cyc > 50) $fatal(1, "world update did not finish");
            end

            if (lfsr !== 16'(e[0]) || fly_x !== 6'(e[1]) || fly_y !== 6'(e[2]) || heading !== 3'(e[3]) ||
                food_x !== 6'(e[4]) || food_y !== 6'(e[5]) || threat_x !== 6'(e[6]) || threat_y !== 6'(e[7]) ||
                eaten !== 16'(e[8]) || caught !== 16'(e[9]) || jumps !== 16'(e[10]) ||
                last_action !== 3'(e[11]) || dut.window_count !== 3'(e[12]) ||
                last_motor[0] !== 8'(m[0]) || last_motor[1] !== 8'(m[1]) || last_motor[2] !== 8'(m[2]) ||
                last_motor[3] !== 8'(m[3]) || last_motor[4] !== 8'(m[4]) || last_motor[5] !== 8'(m[5])) begin
                $display("FAIL step %0d", s + 1);
                $display("  rtl  : lfsr=%0d fly=(%0d,%0d) h=%0d food=(%0d,%0d) threat=(%0d,%0d) e=%0d c=%0d j=%0d act=%0d wc=%0d m=%0d,%0d,%0d,%0d,%0d,%0d",
                         lfsr, fly_x, fly_y, heading, food_x, food_y, threat_x, threat_y, eaten, caught,
                         jumps, last_action, dut.window_count, last_motor[0], last_motor[1], last_motor[2],
                         last_motor[3], last_motor[4], last_motor[5]);
                $display("  model: lfsr=%0d fly=(%0d,%0d) h=%0d food=(%0d,%0d) threat=(%0d,%0d) e=%0d c=%0d j=%0d act=%0d wc=%0d m=%0d,%0d,%0d,%0d,%0d,%0d",
                         e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10], e[11], e[12],
                         m[0], m[1], m[2], m[3], m[4], m[5]);
                $fatal(1, "world state mismatch");
            end
            if (caught != 16'(prev_caught) && e[12] == 0) checked_catch_window++;
            prev_caught = caught;
        end
        $display("PASS tb_fly_world: %0d steps with random output spikes match the model (eaten=%0d caught=%0d jumps=%0d, %0d catches at a window end)",
                 n, eaten, caught, jumps, checked_catch_window);
        $finish;
    end
endmodule
