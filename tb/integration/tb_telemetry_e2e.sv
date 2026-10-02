// tb_telemetry_e2e.sv
// End-to-end telemetry test: fly_core + telemetry, driven by the same
// scenario as tests/vectors/fly_trace.txt. A UART receiver model samples the
// serial line (mid-bit), checks start/stop bits, and writes every received
// byte to BYTES_OUT. tests/check_telemetry.py then decodes the stream with
// the dashboard's parser and checks each packet against the reference model.
//
// Random idle gaps between steps let snapshots land at varied times. With a
// short PERIOD, snapshots are dropped on purpose to test drop accounting.

`timescale 1ns/1ps

module tb_telemetry_e2e #(
    parameter int DIV       = 4,
    parameter int PERIOD    = 5000,
    parameter int NSTEPS    = 300,
    parameter int PROBE     = 29,           // neurons 232..239 (giant fiber, escape DNs)
    parameter int SEED      = 3,
    parameter     TRACE     = "tests/vectors/fly_trace.txt",
    parameter     ROM_PATH  = "rtl/common/network_weights.mem",
    parameter     BYTES_OUT = "build/telemetry_bytes.txt"
);
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic step_req = 0, step_ready, food_present = 0, threat_present = 0, rf = 0, rt = 0;
    logic booted, step_busy, commit, step_done, food_q, threat_q;
    logic [31:0] step_count, cycles_last;
    logic [255:0] spikes;
    logic [7:0][15:0] probe_v;
    logic [5:0] fly_x, fly_y, food_x, food_y, threat_x, threat_y;
    logic [2:0] heading, last_action;
    logic [15:0] eaten, caught, jumps, lfsr, dropped_total, seq_sent;
    logic [5:0][7:0] last_motor;
    logic txd, drop_pulse;

    fly_core #(.ROM_FILE(ROM_PATH)) u_core (
        .clk, .rst, .step_req, .step_ready, .food_present, .threat_present,
        .respawn_food_evt(rf), .respawn_threat_evt(rt), .probe_group(5'(PROBE)),
        .booted, .step_busy, .commit, .step_done, .step_count, .cycles_last, .spikes, .probe_v,
        .food_q, .threat_q, .fly_x, .fly_y, .food_x, .food_y, .threat_x, .threat_y, .heading,
        .eaten, .caught, .jumps, .lfsr, .last_action, .last_motor);

    telemetry #(.DIV(DIV), .PERIOD(PERIOD), .SYSTOLIC(1)) u_tel (
        .clk, .rst, .commit, .spikes, .engine_idle(!step_busy), .running(1'b1),
        .food_present(food_q), .threat_present(threat_q), .step_count, .cycles_last,
        .fly_x, .fly_y, .food_x, .food_y, .threat_x, .threat_y, .heading, .last_action,
        .eaten, .caught, .jumps, .last_motor,
        .probe_group(5'(PROBE)), .probe_v, .txd, .drop_pulse, .dropped_total, .seq_sent);

    task automatic tick(); @(posedge clk); #1; endtask

    // ---------------- UART receiver model ----------------
    int  fo;
    int  nbytes = 0;
    always begin
        logic [7:0] b;
        @(negedge txd);
        if (!rst) begin
            repeat (DIV / 2) @(posedge clk);
            if (txd !== 1'b0) $fatal(1, "false start bit");
            for (int k = 0; k < 8; k++) begin
                repeat (DIV) @(posedge clk);
                b[k] = txd;
            end
            repeat (DIV) @(posedge clk);
            if (txd !== 1'b1) $fatal(1, "framing error: stop bit low");
            $fwrite(fo, "%02x\n", b);
            nbytes++;
        end
    end

    initial begin
        int fd, r, n, f, th, rfi, rti, gap;
        int unsigned lcg;
        reg [8*8192-1:0] rest;          // Icarus: $fgets needs a reg, not a string
        lcg = SEED;
        fo = $fopen(BYTES_OUT, "w");
        fd = $fopen(TRACE, "r");
        if (fd == 0 || fo == 0) $fatal(1, "file open failed");
        r = $fscanf(fd, "%d", n);
        r = $fgets(rest, fd);

        repeat (3) tick();
        rst = 0;
        while (!booted) tick();

        for (int s = 0; s < NSTEPS && s < n; s++) begin
            r = $fscanf(fd, "%d %d %d %d", f, th, rfi, rti);
            r = $fgets(rest, fd);                  // rest of the line: expected state
            food_present = f[0]; threat_present = th[0];
            if (rfi || rti) begin
                rf = rfi[0]; rt = rti[0]; tick(); rf = 0; rt = 0;
            end
            step_req = 1;
            while (!step_ready) tick();
            tick();
            step_req = 0;
            while (!step_done) tick();
            lcg = lcg * 1103515245 + 12345;
            gap = (lcg >> 16) % 2000;
            repeat (gap) tick();
        end
        // let the last packet finish
        repeat (PERIOD + 30000 + 130 * 10 * DIV) tick();
        $fclose(fo);
        $display("DONE tb_telemetry_e2e: %0d steps, %0d bytes, %0d packets sent, %0d dropped",
                 NSTEPS, nbytes, seq_sent, dropped_total);
        $finish;
    end
endmodule
