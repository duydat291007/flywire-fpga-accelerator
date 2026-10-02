// tb_fly_core.sv
// Closed-loop comparison of fly_core against the Python reference trace
// (tests/vectors/fly_trace.txt from model/gen_fly_trace.py).
//
// After every timestep it compares the COMPLETE state: all 256 potentials,
// the 256-bit spike vector, step number, LFSR, fly position and heading,
// food/threat positions, eaten/caught/jump counters, last action, and the
// last motor window. Any same-step spike
// contamination, LIF arithmetic error, or world-rule mismatch shows up as
// the first diverging step.
//
// Also checks the potential probe port and that step requests are refused
// before boot completes.

`timescale 1ns/1ps

module tb_fly_core #(
    parameter int    ENGINE_SYSTOLIC = 1,
    parameter int    ROWS   = 4,
    parameter int    COLS   = 4,
    parameter int    BANKED = 1,
    parameter int    WBUF   = 2,
    parameter        TRACE  = "tests/vectors/fly_trace.txt",
    parameter        ROM_PATH = "rtl/common/network_weights.mem"
);
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    localparam int N = 256;
    logic step_req = 0, step_ready;
    logic food_present = 0, threat_present = 0, rf_evt = 0, rt_evt = 0;
    logic [4:0] probe_group = 0;
    logic booted, step_busy, commit, step_done, food_q, threat_q;
    logic [31:0] step_count, cycles_last;
    logic [N-1:0] spikes;
    logic [7:0][15:0] probe_v;
    logic [5:0] fly_x, fly_y, food_x, food_y, threat_x, threat_y;
    logic [2:0] heading, last_action;
    logic [15:0] eaten, caught, jumps, lfsr;
    logic [5:0][7:0] last_motor;

    fly_core #(.ENGINE_SYSTOLIC(ENGINE_SYSTOLIC), .ROWS(ROWS), .COLS(COLS), .BANKED(BANKED),
               .WBUF(WBUF), .ROM_FILE(ROM_PATH)) dut (
        .clk, .rst, .step_req, .step_ready, .food_present, .threat_present,
        .respawn_food_evt(rf_evt), .respawn_threat_evt(rt_evt), .probe_group,
        .booted, .step_busy, .commit, .step_done, .step_count, .cycles_last, .spikes,
        .probe_v, .food_q, .threat_q, .fly_x, .fly_y, .food_x, .food_y, .threat_x, .threat_y,
        .heading, .eaten, .caught, .jumps, .lfsr, .last_action, .last_motor);

    longint cycle = 0;
    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (cycle > 64'd400_000_000) $fatal(1, "TIMEOUT");
    end

    task automatic tick(); @(posedge clk); #1; endtask

    function automatic logic [15:0] vstate(input int k);
        return dut.vmem[{dut.cur, 8'(k)}];
    endfunction

    initial begin
        int fd, r, n, tmp;
        int f, th, rf, rt, stp, lf, fx, fy, hd, gx, gy, tx, ty, ea, ca, ju, la;
        int m [6];
        logic [N-1:0] sp;
        int V [N];
        longint cyc_min, cyc_max, total_spikes;
        string cfg;

        if (ENGINE_SYSTOLIC != 0)
            $sformat(cfg, "systolic %0dx%0d banked=%0d wbuf=%0d", ROWS, COLS, BANKED, WBUF);
        else cfg = "serial";

        fd = $fopen(TRACE, "r");
        if (fd == 0) $fatal(1, "cannot open %s", TRACE);
        r = $fscanf(fd, "%d", n);

        repeat (3) tick();
        rst = 0;
        // Requests must be refused until the weights are loaded
        step_req = 1;
        tick();
        if (step_ready || step_busy) $fatal(1, "step accepted before boot");
        step_req = 0;
        while (!booted) tick();

        cyc_min = 64'h7fffffff; cyc_max = 0; total_spikes = 0;
        for (int s = 0; s < n; s++) begin
            r = $fscanf(fd, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d", f, th, rf, rt,
                        stp, lf, fx, fy, hd, gx, gy, tx, ty, ea, ca, ju, la);
            for (int d = 0; d < 6; d++) begin r = $fscanf(fd, "%d", tmp); m[d] = tmp; end
            r = $fscanf(fd, "%h", sp);
            for (int k = 0; k < N; k++) begin r = $fscanf(fd, "%d", tmp); V[k] = tmp; end

            food_present = f[0]; threat_present = th[0];
            if (rf || rt) begin
                rf_evt = rf[0]; rt_evt = rt[0];
                tick();
                rf_evt = 0; rt_evt = 0;
            end
            step_req = 1;
            while (!step_ready) tick();
            tick();
            step_req = 0;
            while (!step_done) tick();

            // ---- compare complete state ----
            if (step_count !== 32'(stp) || spikes !== sp || lfsr !== 16'(lf) ||
                fly_x !== 6'(fx) || fly_y !== 6'(fy) || heading !== 3'(hd) ||
                food_x !== 6'(gx) || food_y !== 6'(gy) || threat_x !== 6'(tx) || threat_y !== 6'(ty) ||
                eaten !== 16'(ea) || caught !== 16'(ca) || jumps !== 16'(ju) ||
                last_action !== 3'(la) ||
                last_motor[0] !== 8'(m[0]) || last_motor[1] !== 8'(m[1]) || last_motor[2] !== 8'(m[2]) ||
                last_motor[3] !== 8'(m[3]) || last_motor[4] !== 8'(m[4]) || last_motor[5] !== 8'(m[5])) begin
                $display("FAIL step %0d (%s)", stp, cfg);
                $display("  rtl  : step=%0d lfsr=%0d fly=(%0d,%0d) h=%0d food=(%0d,%0d) threat=(%0d,%0d) eaten=%0d caught=%0d jumps=%0d act=%0d motor=%0d,%0d,%0d,%0d,%0d,%0d",
                         step_count, lfsr, fly_x, fly_y, heading, food_x, food_y, threat_x, threat_y,
                         eaten, caught, jumps, last_action, last_motor[0], last_motor[1], last_motor[2],
                         last_motor[3], last_motor[4], last_motor[5]);
                $display("  model: step=%0d lfsr=%0d fly=(%0d,%0d) h=%0d food=(%0d,%0d) threat=(%0d,%0d) eaten=%0d caught=%0d jumps=%0d act=%0d motor=%0d,%0d,%0d,%0d,%0d,%0d",
                         stp, lf, fx, fy, hd, gx, gy, tx, ty, ea, ca, ju, la, m[0], m[1], m[2], m[3], m[4], m[5]);
                if (spikes !== sp) $display("  spikes differ: rtl^model = %h", spikes ^ sp);
                $fatal(1, "state mismatch");
            end
            for (int k = 0; k < N; k++)
                if (vstate(k) !== 16'(V[k])) begin
                    $display("FAIL step %0d: V[%0d] rtl=%0d model=%0d", stp, k, vstate(k), V[k]);
                    $fatal(1, "potential mismatch");
                end
            // probe port shows the committed potentials of the group selected
            // during the step (it refreshes once per step)
            for (int k = 0; k < 8; k++)
                if (probe_v[k] !== 16'(V[8 * int'(probe_group) + k])) $fatal(1, "probe port mismatch");
            probe_group = 5'((s * 7) % 32);     // select a new group for the next step

            if (cycles_last < cyc_min) cyc_min = cycles_last;
            if (cycles_last > cyc_max) cyc_max = cycles_last;
            total_spikes += $countones(spikes);
        end

        $display("PERF neural_update [%s] cycles_min=%0d cycles_max=%0d", cfg, cyc_min, cyc_max);
        $display("PASS tb_fly_core [%s]: %0d steps match the reference model (%0d spikes, eaten=%0d caught=%0d)",
                 cfg, n, total_spikes, eaten, caught);
        $finish;
    end
endmodule
