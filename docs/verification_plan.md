# Verification plan

Written alongside the specification (`docs/specification.md`) before the RTL,
then extended as the implementation exposed new risks. Results are in
`docs/verification_results.md`; the regression is `scripts/run_regression.py`.

## Strategy

| Layer | Purpose |
|---|---|
| Python reference model (`model/fly_model`) | Independent mathematical definition: plain double-loop matvec, LIF, world rules, packet format. Shares no tiling or scheduling logic with the RTL. |
| Self-checking SV testbenches | Directed + constrained-random stimulus from model-generated vectors; immediate checks of every result and protocol rule. Run in Icarus (4-state, catches X) and Verilator. |
| SystemVerilog assertions (`tb/sva`, bound with `bind`) | Protocol and internal invariants checked every cycle. Run in Verilator and XSim. Simulation assertions, **not** formal proof. |
| UVM environment (`tb/uvm`) | Random operation sequences, monitor-based scoreboard, functional coverage (partial tile × sign × stall, reset phases). Targets XSim. |
| End-to-end checkers (`tests/*.py`) | Decode the serial byte stream with the dashboard's parser and compare to the model. |
| Mutation checks | Inject known bug classes; each must be detected. Measures the tests, not the design. |

Determinism: vector seeds are fixed (MVU 20260930, LIF 11, trace scenario
fixed, testbench LCG seed 1). Every testbench has a global timeout; tb_mvu also
has a 100k-cycle per-command watchdog so deadlocks fail fast.

## Requirements → checks

| # | Requirement (spec §) | Method | Where |
|---|---|---|---|
| R1 | Signed INT8 arithmetic, exact 32-bit results (2.2) | Model comparison; exhaustive extremes ±127/−128; sign mutants | `tb_mvu` cases `extreme_*`, `all_*`; mutants `pe_zero_extend`, `serial_unsigned` |
| R2 | `W[dst][src]` convention, no transposition | Identity, one-hot x, isolated weights | `identity`, `onehot_x*`, `isolated_w*` |
| R3 | Dimensions 1..64 incl. partial tiles; memory outside dim ignored | Dims 1,2,3,4,5,7,8,9,16,17,31,33,63,64 + 30 random; garbage outside dim | `dim*`, `rand*`; mutant `weight_src_mask` |
| R4 | Illegal dims flagged, no results | dim 0 and 65 | `illegal_dim0/65`; SVA `a_illegal_flagged` |
| R5 | Output order, `res_last`, exactly dim results | Every result checked in order | `tb_mvu.run_cmd`; UVM scoreboard |
| R6 | Stable data + metadata under backpressure | Random `res_ready` (up to 95 % stall) | monitor in `tb_mvu`; SVA `a_res_stable`; mutant `ignore_backpressure` |
| R7 | Random input gaps on write ports | `w_valid`/`x_valid` gaps up to 90 % | `stall*_gap*`, random cases |
| R8 | No writes accepted while busy | Monitor + SVA | `a_no_ready_busy`; mutant `write_while_busy` |
| R9 | `done`/`err_dim` one cycle, never premature | Immediate + SVA | `tick_check_done`; `a_done_cause`, `a_no_early_results` |
| R10 | Reset in load, compute, drain phases; clean restart | Reset at 0,1,3,20,100,400,1000 cycles and after 0,1,30,63 results; rerun same command | `reset_*`; SVA `a_reset_idle`; mutant `loader_not_reset` |
| R11 | Stale-state prevention across operations | Back-to-back with reused memory and changing dims | `b2b_*`; mutant `stale_accumulator` |
| R12 | Weight-buffer hazard (WBUF ≥ 2) | Wide arrays (COLS > ROWS) + SVA hazard/occupancy | 2×8 config; `a_no_wbuf_hazard`, `a_busy_count`; mutants `buffer_hazard_*` |
| R13 | Systolic alignment (x meets partial sum) | SVA on every PE | `a_wavefront_aligned`; mutant `skew_valid` |
| R14 | Legal memory addresses, buffer occupancy bounds | SVA | `a_ld_addr`, `a_occupancy`, `a_counter_order`, `a_idx_bound` |
| R15 | LIF bit-exact incl. threshold equality, clamp, leak floor | 9,561 model vectors, 3 thresholds | `tb_lif`; mutants `lif_strict_gt`, `lif_no_clamp` |
| R16 | Same-step consistency; complete recurrent state | 800-step full-state comparison (all V, s, world) in 4 engine configs | `tb_fly_core`; SVA `a_commit_complete`, `a_single_write`, `a_bank_only_at_commit`; mutants `same_step_contamination`, `commit_incomplete` |
| R17 | Inhibition, propagation, food/threat responses, feedback | Model unit tests, then RTL trace equality | `model/tests/test_model.py`; `tb_fly_core` |
| R18 | World rules (move, eat after move, caught, respawn, LFSR) | Trace with eat/caught/respawn events | `tb_fly_core`; mutant `world_eat_before_move` |
| R19 | UART 8N1 framing, LSB first, exact bit time, reset mid-byte | Cycle-exact checker | `tb_uart_tx` (DIV 16, 868); mutant `uart_lsb_msb` |
| R20 | Packet format, byte order, CRC, sequence numbers | Model encoder/decoder tests; RTL bytes decoded by the dashboard parser | `test_model.TestPacket`; `check_telemetry.py`; mutant `crc_init` |
| R21 | Coherent snapshots; activity accumulates; drop accounting | Packets vs model state at the packet's step; forced drops | `telemetry_e2e_{nodrop,drops}`; SVA `a_capture_idle`; mutant `telemetry_no_clear` |
| R22 | Parser: partial reads, garbage, corruption, false sync | Python tests with chunking and corruption | `TestPacket.*` |
| R23 | Board: boot, bouncing buttons → one event, run/pause, reset | Board-level simulation + model state comparison | `tb_basys3_top`, `check_top_state.py`, `check_stream.py` |
| R24 | Functional coverage of MVU operations | UVM covergroups on observed transfers | `mvu_coverage` (XSim) |
| R25 | Timing closure at 100 MHz, resource use | Vivado post-route reports | `scripts/vivado/build.tcl` (pending Vivado run) |
| R26 | Physical board behavior and live telemetry | Hardware test | `docs/board_guide.md` checklist (pending board) |

## Functional coverage model (UVM, `mvu_coverage`)

Sampled from **observed** traffic (monitor), at operation retirement:

* `cp_dim`: 1, below tile, tile, tile+1, middle, N−1, N
* `cp_partial`: dim mod 4 ≠ 0
* `cp_sign`: operands actually accepted inside dim, classified as positive,
  negative, mixed, containing extremes, or binary
* `cp_stall`: at least one output stall during the drain
* cross `partial × sign × stall` (20 bins)
* `cg_illegal`: dim 0, dim > N; `cg_reset`: reset while idle / computing / draining

Code coverage (line/branch/toggle) is a separate XSim option
(`-cc_type sbct`) and is reported separately; it is not merged with
functional coverage.

## Exclusions and known gaps

| Item | Reason |
|---|---|
| x port masking in `mvu_systolic` | Removed: weights of out-of-range rows are already zeroed, so an x mask was an undetectable equivalent mutant |
| PE `pv_out <= pv_in && xv_in` AND term | Equivalent given alignment (proved per cycle by `a_wavefront_aligned`); kept as defense |
| Formal proof | Not attempted; SVA here are simulation checks |
| Multiple outstanding MVU commands | Out of scope by specification (one outstanding operation) |
| UART receive path | Not implemented (telemetry is one-way in v1) |
