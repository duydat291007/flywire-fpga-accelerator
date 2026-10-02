// mvu_uvm_pkg.sv
// UVM 1.2 environment for the matrix-vector units (mvu_serial / mvu_systolic).
//
//   mvu_op_item      one operation: dimension, operands, x load mode,
//                    output-stall probability, optional reset point
//   mvu_driver       pin-level stimulus (writes, command, res_ready, reset)
//   mvu_monitor      observes ACCEPTED transfers only (valid && ready), resets,
//                    done/err, and output stalls; never trusts the driver
//   mvu_scoreboard   shadow of what the DUT actually accepted + independent
//                    reference (plain double loop), in-order result compare
//   mvu_coverage     functional coverage sampled on observed, retired operations
//
// Status: implemented for Vivado XSim's bundled UVM 1.2. Not compiled or run
// in the development environment (no UVM-capable simulator there). See
// docs/verification_results.md for its execution status.

`timescale 1ns/1ps

package mvu_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam int N_MAX = 64;

    typedef enum {SIGN_POS, SIGN_NEG, SIGN_MIXED, SIGN_EXTREME, SIGN_BINARY} sign_cat_e;

    // ======================================================================
    // Sequence item
    // ======================================================================
    class mvu_op_item extends uvm_sequence_item;
        rand int unsigned dim;
        rand bit          reuse_memory;   // keep the previous memory contents
        rand bit          use_bulk;       // binary x through the bulk port
        rand sign_cat_e   sign_cat;
        rand int unsigned stall_pct;      // probability (%) that res_ready is low
        rand int          reset_after;    // -1: none; else cycles after acceptance
        rand int unsigned seed;
        int               W [N_MAX][N_MAX];
        int               x [N_MAX];

        // ---- Distribution ----------------------------------------------
        // XSim 2025.2 did not apply `dist` weights (it drew each value
        // uniformly from its legal set: 499 of 500 items requested a reset
        // against 15 % specified; see BUG-009). So weighted choices are made
        // procedurally in pre_randomize() with $urandom (seeded by -sv_seed,
        // reproducible) and pinned with equality constraints. Directed and
        // fill sequences set use_weights = 0 and give their own targets.
        bit          use_weights = 1;
        bit          first_item  = 0;     // never reuse memory on the first item
        int unsigned min_stall   = 0;     // > 0: always stall heavily (stress test)
        int unsigned t_dim;
        sign_cat_e   t_sign;
        int          t_reset;
        int unsigned t_stall;
        bit          t_reuse;

        // Legal ranges (always active)
        constraint c_range {
            dim inside {[0:N_MAX + 1]};
            stall_pct inside {0, [10:50], [80:95]};
            reset_after inside {-1, [0:3000]};
        }
        // Binary operands always go through the bulk port, and only they do
        constraint c_bulk { use_bulk == (sign_cat == SIGN_BINARY); }
        // Procedural weighted targets
        constraint c_weights {
            use_weights -> (dim == t_dim && sign_cat == t_sign &&
                            stall_pct == t_stall && reset_after == t_reset &&
                            reuse_memory == t_reuse);
        }

        function void pre_randomize();
            int unsigned r;
            r = $urandom_range(79);                         // dim weights sum to 80
            if      (r < 1)  t_dim = 0;                     //  1  illegal 0
            else if (r < 2)  t_dim = N_MAX + 1;             //  1  illegal N+1
            else if (r < 8)  t_dim = 1;                     //  6
            else if (r < 14) t_dim = 2 + $urandom_range(1); //  6  2..3
            else if (r < 20) t_dim = 4;                     //  6
            else if (r < 26) t_dim = 5;                     //  6
            else if (r < 46) t_dim = 6 + $urandom_range(25);  // 20  6..31
            else if (r < 66) t_dim = 32 + $urandom_range(30); // 20  32..62
            else if (r < 72) t_dim = N_MAX - 1;             //  6
            else             t_dim = N_MAX;                 //  8
            t_sign = sign_cat_e'($urandom_range(4));        // 20 % each category (cast here,
                                                            // not inside a constraint: BUG-007)
            r = $urandom_range(99);
            if (min_stall > 0)  t_stall = 80 + $urandom_range(15);
            else if (r < 40)    t_stall = 0;
            else if (r < 80)    t_stall = 10 + $urandom_range(40);
            else                t_stall = 80 + $urandom_range(15);
            r = $urandom_range(99);
            if (r < 85)      t_reset = -1;
            else if (r < 90) t_reset = $urandom_range(40);
            else             t_reset = 41 + $urandom_range(2959);
            t_reuse = !first_item && ($urandom_range(99) < 20);
        endfunction

        // Plain registration (no field macros) plus convert2string: the most
        // portable form across simulators (XSim 2025.2 crashed elaborating the
        // first version of this package; see BUG-007).
        `uvm_object_utils(mvu_op_item)

        function string convert2string();
            return $sformatf("dim=%0d bulk=%0b sign=%s stall=%0d%% reset_after=%0d reuse=%0b",
                             dim, use_bulk, sign_cat.name(), stall_pct, reset_after, reuse_memory);
        endfunction

        function new(string name = "mvu_op_item");
            super.new(name);
        endfunction

        // Operands inside dim follow sign_cat; everything outside dim is
        // random garbage that must never influence a result. A private LCG
        // seeded from the randomized `seed` keeps the item reproducible
        // without disturbing any thread's random state.
        local int unsigned lcg;
        function int unsigned rnd(int unsigned range);   // 0 .. range
            lcg = lcg * 1103515245 + 12345;
            return (lcg >> 8) % (range + 1);
        endfunction

        function void post_randomize();
            lcg = seed;
            for (int i = 0; i < N_MAX; i++) begin
                for (int j = 0; j < N_MAX; j++)
                    W[i][j] = (i < dim && j < dim) ? pick() : int'(rnd(255)) - 128;
                x[i] = (i < dim) ? (use_bulk ? int'(rnd(1)) : pick()) :
                       (use_bulk ? int'(rnd(1)) : int'(rnd(255)) - 128);
            end
        endfunction

        // Each category produces only values that the coverage collector will
        // classify as that category: 127 and -128 appear ONLY in SIGN_EXTREME.
        // (The first version let POS/NEG/MIXED produce them too, so large
        // operations almost always classified as EXTREME and the
        // partial x sign x stall cross stayed at 35 % - coverage-closure fix.)
        function int pick();
            case (sign_cat)
                SIGN_POS:     return int'(rnd(126));             //    0 .. 126
                SIGN_NEG:     return -int'(rnd(126)) - 1;        // -127 .. -1
                SIGN_EXTREME: return rnd(1) ? 127 : -128;
                SIGN_BINARY:  return int'(rnd(1));
                default:      return int'(rnd(253)) - 127;      // -127 .. 126
            endcase
        endfunction
    endclass

    // ======================================================================
    // Observed transaction (from the monitor)
    // ======================================================================
    typedef enum {OBS_WEIGHT, OBS_X, OBS_XBULK, OBS_CMD, OBS_RESULT, OBS_DONE, OBS_RESET} obs_kind_e;
    typedef enum {PH_IDLE, PH_COMPUTE, PH_DRAIN} phase_e;

    class mvu_obs extends uvm_sequence_item;
        obs_kind_e        kind;
        int               a, b, data;        // weight: dst, src, data; x: idx, -, data; cmd: dim
        logic [N_MAX-1:0] bits;
        int               idx;
        bit               last, err, stalled;
        phase_e           phase;             // for resets
        `uvm_object_utils(mvu_obs)
        function new(string name = "mvu_obs"); super.new(name); endfunction
    endclass

    // ======================================================================
    // Sequencer, driver
    // ======================================================================
    typedef uvm_sequencer #(mvu_op_item) mvu_sequencer;

    class mvu_driver extends uvm_driver #(mvu_op_item);
        `uvm_component_utils(mvu_driver)
        virtual mvu_if vif;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db #(virtual mvu_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction

        task run_phase(uvm_phase phase);
            idle();
            vif.drv_cb.rst <= 1'b1;
            repeat (3) @(vif.drv_cb);
            vif.drv_cb.rst <= 1'b0;
            @(vif.drv_cb);
            forever begin
                seq_item_port.get_next_item(req);
                drive_op(req);
                seq_item_port.item_done();
            end
        endtask

        task idle();
            vif.drv_cb.w_valid   <= 0;
            vif.drv_cb.x_valid   <= 0;
            vif.drv_cb.xb_valid  <= 0;
            vif.drv_cb.cmd_valid <= 0;
            vif.drv_cb.res_ready <= 0;
        endtask

        // Hold valid until the DUT accepts (handles any backpressure)
        task drive_op(mvu_op_item it);
            bit aborted;
            if (!it.reuse_memory) begin
                for (int i = 0; i < N_MAX; i++)
                    for (int j = 0; j < N_MAX; j++) begin
                        vif.drv_cb.w_valid <= 1;
                        vif.drv_cb.w_dst   <= i;
                        vif.drv_cb.w_src   <= j;
                        vif.drv_cb.w_data  <= it.W[i][j];
                        do @(vif.drv_cb); while (!vif.drv_cb.w_ready);
                    end
                vif.drv_cb.w_valid <= 0;
                if (it.use_bulk) begin
                    logic [N_MAX-1:0] bits;
                    for (int j = 0; j < N_MAX; j++) bits[j] = it.x[j][0];
                    vif.drv_cb.xb_bits  <= bits;
                    vif.drv_cb.xb_valid <= 1;
                    do @(vif.drv_cb); while (!vif.drv_cb.xb_ready);
                    vif.drv_cb.xb_valid <= 0;
                end else begin
                    for (int j = 0; j < N_MAX; j++) begin
                        vif.drv_cb.x_valid <= 1;
                        vif.drv_cb.x_idx   <= j;
                        vif.drv_cb.x_data  <= it.x[j];
                        do @(vif.drv_cb); while (!vif.drv_cb.x_ready);
                    end
                    vif.drv_cb.x_valid <= 0;
                end
            end
            run_cmd(it, it.reset_after, aborted);
            if (aborted)           // memories survive reset: the same command must work
                run_cmd(it, -1, aborted);
        endtask

        task run_cmd(mvu_op_item it, int reset_after, output bit aborted);
            int cycles = 0;
            aborted = 0;
            vif.drv_cb.cmd_valid <= 1;
            vif.drv_cb.cmd_dim   <= it.dim;
            do @(vif.drv_cb); while (!vif.drv_cb.cmd_ready);
            vif.drv_cb.cmd_valid <= 0;
            if (it.dim < 1 || it.dim > N_MAX) begin
                repeat (3) @(vif.drv_cb);
                return;
            end
            forever begin
                if (reset_after >= 0 && cycles >= reset_after) begin
                    vif.drv_cb.rst <= 1;
                    repeat (2) @(vif.drv_cb);
                    vif.drv_cb.rst <= 0;
                    vif.drv_cb.res_ready <= 0;
                    @(vif.drv_cb);
                    aborted = 1;
                    return;
                end
                vif.drv_cb.res_ready <= ($urandom_range(99) >= it.stall_pct);
                @(vif.drv_cb);
                cycles++;
                if (vif.drv_cb.done) begin
                    vif.drv_cb.res_ready <= 0;
                    return;
                end
                if (cycles > 200_000) `uvm_fatal("TIMEOUT", "operation did not complete")
            end
        endtask
    endclass

    // ======================================================================
    // Monitor: accepted transfers only
    // ======================================================================
    class mvu_monitor extends uvm_monitor;
        `uvm_component_utils(mvu_monitor)
        virtual mvu_if vif;
        uvm_analysis_port #(mvu_obs) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db #(virtual mvu_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction

        function mvu_obs mk(obs_kind_e k);
            mvu_obs o = mvu_obs::type_id::create("o");
            o.kind = k;
            return o;
        endfunction

        task run_phase(uvm_phase phase);
            bit stalled_since_cmd;
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.rst) begin
                    mvu_obs o = mk(OBS_RESET);
                    o.phase = vif.mon_cb.res_valid ? PH_DRAIN : (vif.mon_cb.busy ? PH_COMPUTE : PH_IDLE);
                    ap.write(o);
                    stalled_since_cmd = 0;
                    continue;
                end
                if (vif.mon_cb.w_valid && vif.mon_cb.w_ready) begin
                    mvu_obs o = mk(OBS_WEIGHT);
                    o.a = vif.mon_cb.w_dst; o.b = vif.mon_cb.w_src;
                    o.data = $signed(vif.mon_cb.w_data);
                    ap.write(o);
                end
                if (vif.mon_cb.x_valid && vif.mon_cb.x_ready) begin
                    mvu_obs o = mk(OBS_X);
                    o.a = vif.mon_cb.x_idx; o.data = $signed(vif.mon_cb.x_data);
                    ap.write(o);
                end
                if (vif.mon_cb.xb_valid && vif.mon_cb.xb_ready) begin
                    mvu_obs o = mk(OBS_XBULK);
                    o.bits = vif.mon_cb.xb_bits;
                    ap.write(o);
                end
                if (vif.mon_cb.cmd_valid && vif.mon_cb.cmd_ready) begin
                    mvu_obs o = mk(OBS_CMD);
                    o.a = vif.mon_cb.cmd_dim;
                    stalled_since_cmd = 0;
                    ap.write(o);
                end
                if (vif.mon_cb.res_valid && !vif.mon_cb.res_ready)
                    stalled_since_cmd = 1;
                if (vif.mon_cb.res_valid && vif.mon_cb.res_ready) begin
                    mvu_obs o = mk(OBS_RESULT);
                    o.idx = vif.mon_cb.res_idx; o.data = $signed(vif.mon_cb.res_data);
                    o.last = vif.mon_cb.res_last; o.stalled = stalled_since_cmd;
                    ap.write(o);
                end
                if (vif.mon_cb.done) begin
                    mvu_obs o = mk(OBS_DONE);
                    o.err = vif.mon_cb.err_dim;
                    ap.write(o);
                end
            end
        endtask
    endclass

    // ======================================================================
    // Agent
    // ======================================================================
    class mvu_agent extends uvm_agent;
        `uvm_component_utils(mvu_agent)
        mvu_sequencer sqr;
        mvu_driver    drv;
        mvu_monitor   mon;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            mon = mvu_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sqr = mvu_sequencer::type_id::create("sqr", this);
                drv = mvu_driver::type_id::create("drv", this);
            end
        endfunction
        function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    // ======================================================================
    // Scoreboard: shadow memory of accepted writes + independent reference
    // ======================================================================
    class mvu_scoreboard extends uvm_subscriber #(mvu_obs);
        `uvm_component_utils(mvu_scoreboard)
        int W [N_MAX][N_MAX];
        int x [N_MAX];
        int expected [$];
        int exp_idx;
        int n_ops, n_results, n_errors, n_illegal, n_resets;
        bit expect_err;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void write(mvu_obs t);
            case (t.kind)
                OBS_WEIGHT: W[t.a][t.b] = t.data;
                OBS_X:      x[t.a] = t.data;
                OBS_XBULK:  for (int j = 0; j < N_MAX; j++) x[j] = t.bits[j];
                OBS_CMD: begin
                    expected.delete();
                    exp_idx = 0;
                    expect_err = (t.a < 1 || t.a > N_MAX);
                    if (!expect_err) begin
                        for (int i = 0; i < t.a; i++) begin
                            longint acc = 0;              // plain double loop, no tiling
                            for (int j = 0; j < t.a; j++) acc += W[i][j] * x[j];
                            expected.push_back(int'(acc));
                        end
                        n_ops++;
                    end else n_illegal++;
                end
                OBS_RESULT: begin
                    n_results++;
                    if (exp_idx >= expected.size())
                        `uvm_error("SB", $sformatf("unexpected result idx %0d", t.idx))
                    else begin
                        if (t.idx != exp_idx || t.data != expected[exp_idx] ||
                            t.last != (exp_idx == expected.size() - 1)) begin
                            n_errors++;
                            `uvm_error("SB", $sformatf("result %0d: got idx %0d data %0d last %0b, expected %0d",
                                                       exp_idx, t.idx, t.data, t.last, expected[exp_idx]))
                        end
                        exp_idx++;
                    end
                end
                OBS_DONE: begin
                    if (t.err != expect_err)
                        `uvm_error("SB", $sformatf("err_dim=%0b, expected %0b", t.err, expect_err))
                    if (!expect_err && exp_idx != expected.size())
                        `uvm_error("SB", $sformatf("done after %0d of %0d results", exp_idx, expected.size()))
                    expected.delete();
                end
                OBS_RESET: begin
                    if (expected.size() != 0) n_resets++;
                    expected.delete();     // aborted operation: nothing more is owed
                    exp_idx = 0;
                end
            endcase
        endfunction

        function void check_phase(uvm_phase phase);
            if (expected.size() != 0 && exp_idx != expected.size())
                `uvm_error("SB", $sformatf("%0d results still outstanding", expected.size() - exp_idx))
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SB", $sformatf("%0d operations, %0d results checked, %0d illegal commands, %0d aborted by reset, %0d mismatches",
                                      n_ops, n_results, n_illegal, n_resets, n_errors), UVM_NONE)
        endfunction
    endclass

    // ======================================================================
    // Functional coverage, sampled from observed (accepted) traffic
    // ======================================================================
    class mvu_coverage extends uvm_subscriber #(mvu_obs);
        `uvm_component_utils(mvu_coverage)
        localparam int TILE = 4;      // array dimension used for partial-tile bins

        int W [N_MAX][N_MAX];
        int x [N_MAX];
        int cur_dim;
        sign_cat_e cur_sign;
        bit cur_stalled, cur_partial;
        phase_e rst_phase;

        covergroup cg_op;
            cp_dim: coverpoint cur_dim {
                bins one        = {1};
                bins below_tile = {[2:TILE-1]};
                bins tile       = {TILE};
                bins tile_plus1 = {TILE + 1};
                bins mid        = {[TILE + 2:N_MAX - 2]};
                bins max_m1     = {N_MAX - 1};
                bins max        = {N_MAX};
            }
            cp_partial: coverpoint cur_partial;
            cp_sign:    coverpoint cur_sign;
            cp_stall:   coverpoint cur_stalled;
            x_partial_sign_stall: cross cp_partial, cp_sign, cp_stall;
        endgroup

        // Hit counts per cross bin [partial][sign][stalled], printed at the end
        // so coverage holes are named explicitly, not just as a percentage.
        int cross_hits [2][5][2];

        int ill_dim;
        covergroup cg_illegal;
            coverpoint ill_dim { bins zero = {0}; bins over = {[N_MAX + 1:$]}; }
        endgroup

        covergroup cg_reset;
            coverpoint rst_phase;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_op = new();
            cg_illegal = new();
            cg_reset = new();
        endfunction

        // Classify the operands actually accepted by the DUT inside dim
        function sign_cat_e classify(int d);
            bit pos = 0, neg = 0, ext = 0, nonbin = 0;
            for (int i = 0; i < d; i++) begin
                for (int j = 0; j < d; j++) begin
                    if (W[i][j] > 0) pos = 1;
                    if (W[i][j] < 0) neg = 1;
                    if (W[i][j] == 127 || W[i][j] == -128) ext = 1;
                end
                if (x[i] < 0) neg = 1;
                if (x[i] == 127 || x[i] == -128) ext = 1;
                if (x[i] != 0 && x[i] != 1) nonbin = 1;
            end
            if (!nonbin) return SIGN_BINARY;
            if (ext)     return SIGN_EXTREME;
            if (pos && neg) return SIGN_MIXED;
            return neg ? SIGN_NEG : SIGN_POS;
        endfunction

        function void write(mvu_obs t);
            case (t.kind)
                OBS_WEIGHT: W[t.a][t.b] = t.data;
                OBS_X:      x[t.a] = t.data;
                OBS_XBULK:  for (int j = 0; j < N_MAX; j++) x[j] = t.bits[j];
                OBS_CMD: begin
                    cur_dim = t.a;
                    if (t.a < 1 || t.a > N_MAX) begin
                        ill_dim = t.a;
                        cg_illegal.sample();
                    end
                    else begin
                        cur_sign = classify(t.a);
                        cur_partial = (t.a % TILE) != 0;
                    end
                end
                OBS_RESULT: if (t.last) begin        // sample when the op retires
                    cur_stalled = t.stalled;
                    cg_op.sample();
                    cross_hits[cur_partial][int'(cur_sign)][cur_stalled]++;
                end
                OBS_RESET: begin
                    rst_phase = t.phase;
                    cg_reset.sample();
                end
                default: ;
            endcase
        endfunction

        function void report_phase(uvm_phase phase);
            string line;
            sign_cat_e e;
            for (int p = 0; p < 2; p++)
                for (int sg = 0; sg < 5; sg++) begin
                    e = sign_cat_e'(sg);
                    line = $sformatf("cross bin partial=%0d sign=%-12s  no-stall %4d  stalled %4d%s",
                                     p, e.name(), cross_hits[p][sg][0], cross_hits[p][sg][1],
                                     (cross_hits[p][sg][0] == 0 || cross_hits[p][sg][1] == 0) ? "   <-- HOLE" : "");
                    `uvm_info("COVBIN", line, UVM_NONE)
                end
            `uvm_info("COV", $sformatf("functional coverage: op %.1f%% (partial x sign x stall %.1f%%), illegal %.1f%%, reset phases %.1f%%",
                                       cg_op.get_coverage(), cg_op.x_partial_sign_stall.get_coverage(),
                                       cg_illegal.get_coverage(), cg_reset.get_coverage()), UVM_NONE)
        endfunction
    endclass

    // ======================================================================
    // Environment
    // ======================================================================
    class mvu_env extends uvm_env;
        `uvm_component_utils(mvu_env)
        mvu_agent      agent;
        mvu_scoreboard sb;
        mvu_coverage   cov;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            agent = mvu_agent::type_id::create("agent", this);
            sb    = mvu_scoreboard::type_id::create("sb", this);
            cov   = mvu_coverage::type_id::create("cov", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            agent.mon.ap.connect(sb.analysis_export);
            agent.mon.ap.connect(cov.analysis_export);
        endfunction
    endclass

    // ======================================================================
    // Sequences
    // ======================================================================
    class mvu_random_seq extends uvm_sequence #(mvu_op_item);
        `uvm_object_utils(mvu_random_seq)
        int n = 50;
        int stall_min = 0, reset_pct = -1;
        bit closure = 1;          // finish with one targeted operation per cross bin
        int gen_sign [5];         // histogram of what the random phase generated
        int gen_bulk, gen_nostall, gen_reuse, gen_reset;
        function new(string name = "mvu_random_seq"); super.new(name); endfunction
        task body();
            int smin;
            smin = stall_min;
            for (int k = 0; k < n; k++) begin
                mvu_op_item it = mvu_op_item::type_id::create("it");
                it.first_item = (k == 0);
                it.min_stall  = smin;
                start_item(it);
                if (!it.randomize())
                    `uvm_fatal("RAND", "randomize failed")
                if (reset_pct >= 0)
                    it.reset_after = ($urandom_range(99) < reset_pct) ? $urandom_range(3000) : -1;
                gen_sign[int'(it.sign_cat)]++;
                if (it.use_bulk)          gen_bulk++;
                if (it.stall_pct == 0)    gen_nostall++;
                if (it.reuse_memory)      gen_reuse++;
                if (it.reset_after >= 0)  gen_reset++;
                finish_item(it);
            end
            // What the random phase GENERATED (compare with what coverage observed)
            `uvm_info("GEN", $sformatf({"random phase, %0d items: sign POS %0d NEG %0d MIXED %0d ",
                                        "EXTREME %0d BINARY %0d | bulk %0d | stall_pct=0 %0d | ",
                                        "reuse %0d | reset %0d"},
                                       n, gen_sign[0], gen_sign[1], gen_sign[2], gen_sign[3],
                                       gen_sign[4], gen_bulk, gen_nostall, gen_reuse, gen_reset),
                      UVM_NONE)
            if (closure) fill_cross();
        endtask

        // Coverage-driven fill: one randomized operation aimed at each
        // partial x sign x stall bin. Values inside the bin stay random.
        // Variables are computed outside `randomize() with` (see BUG-007).
        task fill_cross();
            for (int p = 0; p < 2; p++)
                for (int sg = 0; sg < 5; sg++)
                    for (int st = 0; st < 2; st++) begin
                        mvu_op_item it = mvu_op_item::type_id::create("fill");
                        int d, sp;
                        sign_cat_e sc;
                        // partial: 5, 9, ..., 61 (never a multiple of 4, >= 5 results)
                        // full:    4, 8, ..., 64
                        d  = p ? 5 + 4 * $urandom_range(14) : 4 * (1 + $urandom_range(15));
                        sc = sign_cat_e'(sg);
                        // 85 lies inside the legal stall ranges (c_range); 70 would
                        // make randomize() fail
                        sp = st ? 85 : 0;
                        it.use_weights = 0;
                        start_item(it);
                        if (!it.randomize() with { dim == d; sign_cat == sc; stall_pct == sp;
                                                   reset_after == -1; reuse_memory == 0; })
                            `uvm_fatal("RAND", "fill randomize failed")
                        finish_item(it);
                    end
        endtask
    endclass

    // Directed: required dimensions with each operand category, no stalls
    class mvu_directed_seq extends uvm_sequence #(mvu_op_item);
        `uvm_object_utils(mvu_directed_seq)
        function new(string name = "mvu_directed_seq"); super.new(name); endfunction
        // Required dimensions, including the two illegal ones
        function int dim_at(int k);
            case (k)
                0: return 1;   1: return 3;   2: return 4;   3: return 5;
                4: return 63;  5: return 64;  6: return 0;   default: return 65;
            endcase
        endfunction

        task body();
            for (int k = 0; k < 8; k++)
                for (int s = 0; s < 5; s++) begin
                    mvu_op_item it = mvu_op_item::type_id::create("it");
                    int d;
                    sign_cat_e sc;
                    d  = dim_at(k);
                    // Cast outside the constraint: an enum cast of a loop
                    // variable inside `randomize() with` crashed XSim 2025.2's
                    // elaborator (found with scripts/vivado/uvm_bisect.py; BUG-007).
                    sc = sign_cat_e'(s);
                    it.use_weights = 0;
                    start_item(it);
                    if (!it.randomize() with { dim == d; sign_cat == sc;
                                               reuse_memory == 0; reset_after == -1; stall_pct == 0; })
                        `uvm_fatal("RAND", "randomize failed")
                    finish_item(it);
                end
        endtask
    endclass

    // ======================================================================
    // Tests
    // ======================================================================
    class mvu_base_test extends uvm_test;
        `uvm_component_utils(mvu_base_test)
        mvu_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = mvu_env::type_id::create("env", this);
        endfunction
        function void report_phase(uvm_phase phase);
            uvm_report_server rs = uvm_report_server::get_server();
            if (rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL) == 0)
                $display("PASS %s", get_type_name());
            else
                $display("FAIL %s", get_type_name());
        endfunction
    endclass

    class mvu_directed_test extends mvu_base_test;
        `uvm_component_utils(mvu_directed_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            mvu_directed_seq s = mvu_directed_seq::type_id::create("s");
            phase.raise_objection(this);
            s.start(env.agent.sqr);
            phase.drop_objection(this);
        endtask
    endclass

    class mvu_random_test extends mvu_base_test;
        `uvm_component_utils(mvu_random_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            mvu_random_seq s = mvu_random_seq::type_id::create("s");
            int n;
            if ($value$plusargs("NOPS=%d", n)) s.n = n; else s.n = 500;
            phase.raise_objection(this);
            s.start(env.agent.sqr);
            phase.drop_objection(this);
        endtask
    endclass

    class mvu_stress_test extends mvu_base_test;      // heavy stalls and resets
        `uvm_component_utils(mvu_stress_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            mvu_random_seq s = mvu_random_seq::type_id::create("s");
            s.n = 80; s.stall_min = 60; s.reset_pct = 40;
            phase.raise_objection(this);
            s.start(env.agent.sqr);
            phase.drop_objection(this);
        endtask
    endclass
endpackage
