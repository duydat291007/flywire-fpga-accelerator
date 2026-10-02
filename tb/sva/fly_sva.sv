// fly_sva.sv
// Concurrent assertions for fly_core and telemetry (simulation assertions,
// not formal proof). Attached with `bind` at the bottom of this file.

`timescale 1ns/1ps

module fly_core_sva (
    input logic        clk,
    input logic        rst,
    input logic        in_commit,      // st == S_COMMIT
    input logic        cur,
    input logic [255:0] written,
    input logic        booted,
    input logic        w_valid,
    input logic        w_ready,
    input logic        lw_valid,       // LIF pipeline write
    input logic [7:0]  lw_idx,
    input logic        step_req,
    input logic        step_ready
);
    // Legal state-bank commit: every neuron of the next bank was written
    a_commit_complete: assert property (@(posedge clk) disable iff (rst)
        in_commit |-> written == '1) else $error("commit before all 256 neurons written");

    // The bank-select bit changes only as the result of a commit
    a_bank_only_at_commit: assert property (@(posedge clk) disable iff (rst)
        $changed(cur) |-> $past(in_commit)) else $error("bank select changed outside commit");

    // Each neuron is written at most once per timestep (no double update)
    a_single_write: assert property (@(posedge clk) disable iff (rst)
        lw_valid |-> !written[lw_idx]) else $error("neuron updated twice in one step");

    // Boot writes are never backpressured (the MVU is idle during boot)
    a_boot_never_stalls: assert property (@(posedge clk) disable iff (rst)
        w_valid |-> w_ready) else $error("boot write stalled");

    // No step can start before the weights are loaded
    a_no_step_before_boot: assert property (@(posedge clk) disable iff (rst)
        step_ready |-> booted) else $error("step_ready before boot");

endmodule

module telemetry_sva (
    input logic       clk,
    input logic       rst,
    input logic       capture,
    input logic       engine_idle,
    input logic       sending,
    input logic       commit,
    input logic [6:0] idx,
    input logic       u_valid,
    input logic       u_ready,
    input logic [7:0] pbyte
);
    // Coherent snapshots: capture only between timesteps and never with a commit
    a_capture_idle: assert property (@(posedge clk) disable iff (rst)
        capture |-> engine_idle && !commit) else $error("snapshot captured mid-step");

    // A packet is never restarted while one is being sent
    a_no_overlap: assert property (@(posedge clk) disable iff (rst)
        capture |-> !sending) else $error("capture while sending");

    // Byte index stays inside the 119-byte packet
    a_idx_bound: assert property (@(posedge clk) disable iff (rst)
        sending |-> idx < 7'd119) else $error("packet index out of range");

    // The byte offered to the UART is stable until accepted
    a_byte_stable: assert property (@(posedge clk) disable iff (rst)
        u_valid && !u_ready |=> $stable(pbyte) || !u_valid) else $error("UART byte changed while waiting");
endmodule

module fly_binds;
    bind fly_core fly_core_sva u_core_sva (
        .clk, .rst, .in_commit(st == S_COMMIT), .cur, .written, .booted, .w_valid, .w_ready,
        .lw_valid, .lw_idx, .step_req, .step_ready);
    bind telemetry telemetry_sva u_tel_sva (
        .clk, .rst, .capture, .engine_idle, .sending, .commit, .idx, .u_valid, .u_ready, .pbyte);
endmodule
