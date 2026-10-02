// tb_mvu.sv
// Self-checking integration testbench for mvu_serial / mvu_systolic.
//
// Stimulus and expected results come from tests/vectors/mvu_cases.txt, which
// model/gen_mvu_vectors.py produces with the independent Python reference.
// The testbench never computes expected values itself.
//
// Checked on every case:
//   - result order 0..dim-1, values, res_last, exactly dim results
//   - output held stable (valid, data, idx, last) while stalled
//   - done/err_dim exactly one cycle after retirement, never earlier
//   - writes are backpressured while busy (w_ready/x_ready/xb_ready low)
//   - reset in load/compute/drain phases aborts cleanly, and the reissued
//     command then produces correct results (stale-state check)
//   - illegal dimensions: accepted, no results, done+err_dim next cycle
//
// Runs on Icarus Verilog (-g2012) and Verilator (--binary --timing).

`timescale 1ns/1ps

module tb_mvu #(
    parameter int    USE_SERIAL = 0,
    parameter int    ROWS       = 4,
    parameter int    COLS       = 4,
    parameter int    BANKED     = 1,
    parameter int    WBUF       = 2,
    parameter int    SEED       = 1,
    parameter int    MAX_CASES  = 100000,
    parameter string VECTORS    = "tests/vectors/mvu_cases.txt"
);

    localparam int N_MAX = 64;
    localparam int AW    = 6;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic           w_valid = 0, w_ready;
    logic [AW-1:0]  w_dst = 0, w_src = 0;
    logic [7:0]     w_data = 0;
    logic           x_valid = 0, x_ready;
    logic [AW-1:0]  x_idx = 0;
    logic [7:0]     x_data = 0;
    logic           xb_valid = 0, xb_ready;
    logic [N_MAX-1:0] xb_bits = 0;
    logic           cmd_valid = 0, cmd_ready;
    logic [AW:0]    cmd_dim = 0;
    logic           res_valid, res_ready = 0, res_last;
    logic [31:0]    res_data;
    logic [AW-1:0]  res_idx;
    logic           busy, done, err_dim;

    generate
        if (USE_SERIAL != 0) begin : g_dut
            mvu_serial #(.N_MAX(N_MAX)) dut (.*);
        end else begin : g_dut
            mvu_systolic #(.N_MAX(N_MAX), .ROWS(ROWS), .COLS(COLS),
                           .BANKED(BANKED), .WBUF(WBUF)) dut (.*);
        end
    endgenerate

    // ------------------------------------------------------------------
    // Global cycle counter and timeout
    // ------------------------------------------------------------------
    longint cycle = 0;
    always @(posedge clk) cycle <= cycle + 1;

    localparam longint TIMEOUT_CYCLES = 20_000_000;
    always @(posedge clk)
        if (cycle > TIMEOUT_CYCLES) begin
            $display("FAIL: global timeout");
            $fatal(1, "TIMEOUT");
        end

    // ------------------------------------------------------------------
    // Continuous protocol monitor (independent of the driving code)
    // ------------------------------------------------------------------
    logic        prev_stalled = 0;
    logic [31:0] prev_data;
    logic [AW-1:0] prev_idx;
    logic        prev_last;
    int          stall_cycles = 0;
    int          errors = 0;

    always @(posedge clk) begin
        if (!rst) begin
            if (prev_stalled) begin
                if (res_valid !== 1'b1 || res_data !== prev_data ||
                    res_idx !== prev_idx || res_last !== prev_last) begin
                    $display("FAIL [%0t] output changed while stalled", $time);
                    errors++;
                end
            end
            if (busy && (w_ready || x_ready || xb_ready || cmd_ready)) begin
                $display("FAIL [%0t] ready asserted while busy", $time);
                errors++;
            end
            if (res_valid && !busy) begin
                $display("FAIL [%0t] res_valid while not busy", $time);
                errors++;
            end
            if (done && busy) begin
                $display("FAIL [%0t] done while busy", $time);
                errors++;
            end
        end
        prev_stalled <= !rst && res_valid && !res_ready;
        prev_data    <= res_data;
        prev_idx     <= res_idx;
        prev_last    <= res_last;
        if (!rst && res_valid && !res_ready) stall_cycles++;
    end

    // ------------------------------------------------------------------
    // Case data
    // ------------------------------------------------------------------
    int fd;
    int W [N_MAX][N_MAX];
    int X [N_MAX];
    int E [N_MAX];
    int n_exp;

    int unsigned rng_state;
    function automatic int unsigned rnd100();
        rng_state = rng_state * 1103515245 + 12345;   // deterministic LCG
        return (rng_state >> 8) % 100;
    endfunction

    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic write_weights(input int gap);
        for (int i = 0; i < N_MAX; i++)
            for (int j = 0; j < N_MAX; j++) begin
                while (rnd100() < gap) begin
                    w_valid = 0;
                    tick();
                end
                w_valid = 1; w_dst = AW'(i); w_src = AW'(j); w_data = 8'(W[i][j]);
                @(posedge clk);
                if (!w_ready) $fatal(1, "w_ready low while idle");
                #1;
            end
        w_valid = 0;
    endtask

    task automatic write_x(input int xmode, input int gap);
        if (xmode == 1) begin
            for (int j = 0; j < N_MAX; j++) xb_bits[j] = X[j][0];
            xb_valid = 1;
            @(posedge clk);
            if (!xb_ready) $fatal(1, "xb_ready low while idle");
            #1;
            xb_valid = 0;
        end else begin
            for (int j = 0; j < N_MAX; j++) begin
                while (rnd100() < gap) begin
                    x_valid = 0;
                    tick();
                end
                x_valid = 1; x_idx = AW'(j); x_data = 8'(X[j]);
                @(posedge clk);
                if (!x_ready) $fatal(1, "x_ready low while idle");
                #1;
            end
            x_valid = 0;
        end
    endtask

    task automatic pulse_reset();
        rst = 1;
        tick();
        tick();
        rst = 0;
        if (busy !== 1'b0 || res_valid !== 1'b0 || done !== 1'b0)
            $fatal(1, "state not idle after reset: busy=%b res_valid=%b done=%b",
                   busy, res_valid, done);
    endtask

    // completed = 1 if the command finished, 0 if a reset aborted it.
    // cycles: acceptance-to-done latency (reported on PERF lines).
    // (Written without `return` because Icarus does not allow it in tasks.)
    task automatic run_cmd(input int cid, input int dim, input int stall,
                           input int rst_at, input int rst_k,
                           output int completed, output longint cycles);
        int got;
        int finished;
        longint t_acc;
        completed = 0;
        finished = 0;
        got = 0;
        cycles = 0;

        cmd_valid = 1; cmd_dim = (AW+1)'(dim);
        @(posedge clk);
        if (!cmd_ready) $fatal(1, "cmd_ready low while idle");
        t_acc = cycle;
        #1;
        cmd_valid = 0;

        if (dim < 1 || dim > N_MAX) begin
            if (done !== 1'b1 || err_dim !== 1'b1 || busy !== 1'b0)
                $fatal(1, "case %0d: illegal dim %0d not flagged (done=%b err=%b busy=%b)",
                       cid, dim, done, err_dim, busy);
            repeat (20) begin
                tick();
                if (res_valid || busy || done) $fatal(1, "activity after illegal command");
            end
            completed = 1;
            cycles = 1;
            finished = 1;
        end

        while (!finished) begin
            if (rst_at >= 0 && (cycle - t_acc) >= rst_at) begin
                pulse_reset();                       // reset during load/compute
                finished = 1;
            end else begin
                // Per-command watchdog: the slowest legal operation is ~6.7k
                // cycles plus stalls, so 100k cycles means a deadlock.
                if (cycle - t_acc > 100_000)
                    $fatal(1, "case %0d: operation timeout after %0d results (deadlock)", cid, got);
                res_ready = (rnd100() >= stall);
                @(posedge clk);
                if (done) $fatal(1, "case %0d: premature done after %0d results", cid, got);
                if (res_valid && res_ready) begin
                    if (res_idx !== AW'(got))
                        $fatal(1, "case %0d: idx %0d, expected %0d", cid, res_idx, got);
                    if ($signed(res_data) !== E[got]) begin
                        $display("FAIL case %0d dim %0d: y[%0d] expected %0d, got %0d",
                                 cid, dim, got, E[got], $signed(res_data));
                        $fatal(1, "result mismatch");
                    end
                    if (res_last !== (got == dim - 1))
                        $fatal(1, "case %0d: res_last wrong at %0d", cid, got);
                    got++;
                end
                #1;
                res_ready = 0;
                if (got == dim) begin
                    tick_check_done(cid);
                    cycles = cycle - t_acc;
                    completed = 1;
                    finished = 1;
                end else if (rst_k >= 0 && got == rst_k && res_valid) begin
                    pulse_reset();                   // reset during drain
                    finished = 1;
                end
            end
        end
    endtask

    // Called 1 ns after the retiring edge: done must be high now, for one cycle.
    task automatic tick_check_done(input int cid);
        if (done !== 1'b1 || err_dim !== 1'b0 || busy !== 1'b0)
            $fatal(1, "case %0d: done/busy wrong after retirement (done=%b err=%b busy=%b)",
                   cid, done, err_dim, busy);
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        int n_cases, cid, dim, reuse, xmode, stall, gap, rst_at, rst_k, r, completed;
        int passed;
        int tmp;
        longint cycles;
        string cfg;

        rng_state = SEED;
        passed = 0;
        if (USE_SERIAL != 0) cfg = "serial";
        else $sformat(cfg, "systolic %0dx%0d banked=%0d wbuf=%0d", ROWS, COLS, BANKED, WBUF);
        $display("tb_mvu: %s, seed %0d, vectors %s", cfg, SEED, VECTORS);

        fd = $fopen(VECTORS, "r");
        if (fd == 0) $fatal(1, "cannot open %s", VECTORS);
        r = $fscanf(fd, "%d", n_cases);

        repeat (3) tick();
        rst = 0;
        tick();

        for (int c = 0; c < n_cases && c < MAX_CASES; c++) begin
            r = $fscanf(fd, "%d %d %d %d %d %d %d %d", cid, dim, reuse, xmode, stall, gap,
                        rst_at, rst_k);
            if (r != 8) $fatal(1, "vector file format error at case %0d", c);
            if (!reuse) begin
                for (int i = 0; i < N_MAX; i++)
                    for (int j = 0; j < N_MAX; j++) begin
                        r = $fscanf(fd, "%d", tmp);   // Icarus: scan into a scalar
                        W[i][j] = tmp;
                    end
                for (int j = 0; j < N_MAX; j++) begin
                    r = $fscanf(fd, "%d", tmp);
                    X[j] = tmp;
                end
            end
            r = $fscanf(fd, "%d", n_exp);
            for (int i = 0; i < n_exp; i++) begin
                r = $fscanf(fd, "%d", tmp);
                E[i] = tmp;
            end

            if (!reuse) begin
                write_weights(gap);
                write_x(xmode, gap);
            end

            run_cmd(cid, dim, stall, rst_at, rst_k, completed, cycles);
            if (!completed) begin
                // Aborted by reset: memories persist, so the same command must work
                run_cmd(cid, dim, stall, -1, -1, completed, cycles);
                if (!completed) $fatal(1, "case %0d: rerun after reset did not complete", cid);
            end
            if (rst_at < 0 && rst_k < 0)
                $display("PERF case=%0d dim=%0d stall=%0d cycles=%0d", cid, dim, stall, cycles);
            passed++;
            tick();
        end

        if (errors != 0) begin
            $display("FAIL tb_mvu: %0d monitor errors", errors);
            $fatal(1, "monitor errors");
        end
        $display("PASS tb_mvu [%s]: %0d cases, %0d stall cycles observed", cfg, passed,
                 stall_cycles);
        $finish;
    end

endmodule
