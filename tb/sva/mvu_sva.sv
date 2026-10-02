// mvu_sva.sv
// Concurrent assertions for the matrix-vector units, attached with `bind`
// (see the bottom of this file) so the RTL itself stays assertion-free.
//
// These are simulation assertions: they check the scenarios the testbenches
// exercise. They are not a formal proof.
//
// Tools: Verilator 5 (--assert), Vivado XSim. Icarus Verilog does not support
// concurrent assertions; the Icarus regression relies on the testbench's own
// immediate checks, which cover the interface properties below.

`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Interface properties, common to mvu_serial and mvu_systolic
// ---------------------------------------------------------------------------
module mvu_if_sva #(parameter int N_MAX = 64) (
    input logic                     clk,
    input logic                     rst,
    input logic                     busy,
    input logic                     done,
    input logic                     err_dim,
    input logic                     cmd_valid,
    input logic                     cmd_ready,
    input logic [$clog2(N_MAX):0]   cmd_dim,
    input logic                     w_ready,
    input logic                     x_ready,
    input logic                     xb_ready,
    input logic                     res_valid,
    input logic                     res_ready,
    input logic [31:0]              res_data,
    input logic [$clog2(N_MAX)-1:0] res_idx,
    input logic                     res_last
);
    wire illegal_cmd = cmd_valid && cmd_ready &&
                       (cmd_dim == 0 || cmd_dim > ($clog2(N_MAX)+1)'(N_MAX));

    // Stable data and metadata while valid is asserted and ready is low
    a_res_stable: assert property (@(posedge clk) disable iff (rst)
        res_valid && !res_ready |=> res_valid && $stable(res_data) &&
                                    $stable(res_idx) && $stable(res_last))
        else $error("result changed while stalled");

    // No configuration or command accepted while busy
    a_no_ready_busy: assert property (@(posedge clk) disable iff (rst)
        busy |-> !cmd_ready && !w_ready && !x_ready && !xb_ready)
        else $error("ready asserted while busy");

    // Results only while an operation is active
    a_valid_implies_busy: assert property (@(posedge clk) disable iff (rst)
        res_valid |-> busy) else $error("res_valid while idle");

    // done only follows retirement of the last result or an illegal command
    a_done_cause: assert property (@(posedge clk) disable iff (rst)
        done |-> $past(res_valid && res_ready && res_last) || $past(illegal_cmd))
        else $error("done without a cause (premature completion)");
    a_done_idle: assert property (@(posedge clk) disable iff (rst)
        done |-> !busy) else $error("done while busy");
    a_err_with_done: assert property (@(posedge clk) disable iff (rst)
        err_dim |-> done) else $error("err_dim without done");
    a_illegal_flagged: assert property (@(posedge clk) disable iff (rst)
        illegal_cmd |=> done && err_dim && !busy) else $error("illegal dim not flagged");

    // Retirement makes the unit idle; the last result is the last one
    a_retire: assert property (@(posedge clk) disable iff (rst)
        res_valid && res_ready && res_last |=> !busy && !res_valid && done)
        else $error("did not retire after last result");

    // Reset / abort: one cycle after reset everything is idle
    a_reset_idle: assert property (@(posedge clk)
        rst |=> !busy && !res_valid && !done) else $error("not idle after reset");

    // No unknown control outputs after reset
    a_known: assert property (@(posedge clk) disable iff (rst)
        !$isunknown({busy, done, err_dim, res_valid, cmd_ready}))
        else $error("unknown control signal");
endmodule

// ---------------------------------------------------------------------------
// Internal properties of mvu_systolic
// ---------------------------------------------------------------------------
module mvu_systolic_sva #(
    parameter int N_MAX = 64, parameter int WBUF = 2,
    parameter int TW = 8, parameter int SEL_W = 1, parameter int AW = 6
) (
    input logic             clk,
    input logic             rst,
    input logic [1:0]       state,
    input logic             ld_issue,
    input logic             ld_active,
    input logic [AW:0]      ld_src,
    input logic [AW:0]      ld_dst0,
    input logic             wl_v,
    input logic [SEL_W-1:0] wl_sel,
    input logic [WBUF-1:0]  buf_busy,
    input logic [TW-1:0]    ld_started,
    input logic [TW-1:0]    ld_done,
    input logic [TW-1:0]    lc_count,
    input logic [TW-1:0]    fin_count,
    input logic [SEL_W-1:0] fin_buf,
    input logic [TW-1:0]    total_q,
    input logic             res_valid
);
    localparam logic [1:0] S_RUN = 2'd1;

    function automatic logic buf_in_flight(input logic [SEL_W-1:0] b,
                                           input logic [TW-1:0] fin, input logic [TW-1:0] launched,
                                           input logic [SEL_W-1:0] fbuf);
        logic hit = 1'b0;
        logic [TW-1:0] n = launched - fin;          // wavefronts launched, not finished
        for (int k = 0; k < WBUF; k++)
            if (k < n && ((fbuf + k) % WBUF) == b) hit = 1'b1;
        return hit;
    endfunction

    // Legal memory addresses: every issued weight read is inside the matrix
    a_ld_addr: assert property (@(posedge clk) disable iff (rst)
        ld_issue |-> ld_src < (AW+1)'(N_MAX) && ld_dst0 < (AW+1)'(N_MAX))
        else $error("weight read address out of range");

    // Buffer hazard: never write a weight buffer that an in-flight wavefront uses
    a_no_wbuf_hazard: assert property (@(posedge clk) disable iff (rst)
        wl_v |-> !buf_in_flight(wl_sel, fin_count, lc_count, fin_buf))
        else $error("weight buffer overwritten while in use");

    // Occupancy bounds: pipeline counters stay ordered and bounded by WBUF
    a_counter_order: assert property (@(posedge clk) disable iff (rst || state != S_RUN)
        fin_count <= lc_count && lc_count <= ld_done && ld_done <= ld_started &&
        ld_started <= total_q) else $error("tile counters out of order");
    a_occupancy: assert property (@(posedge clk) disable iff (rst || state != S_RUN)
        (ld_started - fin_count) <= TW'(WBUF)) else $error("more tiles in flight than buffers");
    // A buffer is busy from the start of its load until its tile finishes;
    // ld_started counts completed loads, so add the load in progress.
    a_busy_count: assert property (@(posedge clk) disable iff (rst || state != S_RUN)
        $countones(buf_busy) == (ld_started - fin_count) + TW'(ld_active))
        else $error("buffer bookkeeping");

    // No premature completion: results only after every tile has finished
    a_no_early_results: assert property (@(posedge clk) disable iff (rst)
        res_valid |-> fin_count == total_q) else $error("results before all tiles finished");
endmodule

// PE alignment: in every row below the first, the partial sum arriving from
// above must meet the x value arriving from the left in the same cycle.
module systolic_array_sva #(parameter int ROWS = 4, parameter int COLS = 4) (
    input logic clk,
    input logic rst,
    input logic [ROWS*COLS-1:0] xv_in_flat,
    input logic [ROWS*COLS-1:0] pv_in_flat
);
    a_wavefront_aligned: assert property (@(posedge clk) disable iff (rst)
        xv_in_flat == pv_in_flat) else $error("x and partial sum misaligned in array");
endmodule
