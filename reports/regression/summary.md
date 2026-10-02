# Regression summary

- Date: 2026-10-02T11:42:24
- Host: `vm` (Linux-6.18.44-fc-v51-x86_64-with-glibc2.39)
- Python 3.11.15; Icarus Verilog version 12.0 (stable) (); Verilator 5.020 2024-01-01 rev (Debian 5.020-1)
- Source revision: uncommitted working tree (no git HEAD)
- Vector seeds: MVU 20260930, LIF 11, trace scenario fixed; tb_mvu seed 1
- **62 / 62 passed**

| Test | Simulator | Result | Time (s) | Detail |
|---|---|---|---|---|
| python_unittest | python | PASS | 11.2 | 27 tests |
| gen_export_rtl | python | PASS | 0.0 | exported 2265 nonzero synapses, threshold 100, to /home/claude/fly-accel/rtl/common |
| gen_gen_mvu_vectors | python | PASS | 0.3 | wrote 86 cases (seed 20260930) to /home/claude/fly-accel/tests/vectors/mvu_cases.txt |
| gen_gen_fly_trace | python | PASS | 23.2 | wrote 700 steps to /home/claude/fly-accel/tests/vectors/fly_trace.txt: eaten=5 caught=2 jumps=15 actions(walk,back,jump,eat,blocked)=[64, 0, 15, 5, 3] spikes=1877 |
| gen_gen_fly_trace_short | python | PASS | 1.3 | wrote 44 steps to /home/claude/fly-accel/tests/vectors/fly_trace_short.txt: eaten=1 caught=0 jumps=2 actions(walk,back,jump,eat,blocked)=[2, 0, 2, 1, 0] spikes=318 |
| gen_gen_world_vectors | python | PASS | 0.2 | wrote 6000 world steps to /home/claude/fly-accel/tests/vectors/world_vectors.txt: eaten=21 caught=8 jumps=91 actions(walk,back,jump,eat,blocked)=[188, 408, 91, 21, 42] |
| gen_gen_lif_vectors | python | PASS | 0.2 | wrote 9561 LIF cases to /home/claude/fly-accel/tests/vectors/lif_cases.txt |
| uart_tx_div16 | icarus | PASS | 0.1 | PASS tb_uart_tx: 200 bytes, DIV=16, cycle-exact framing |
| uart_tx_div868 | icarus | PASS | 0.1 | PASS tb_uart_tx: 6 bytes, DIV=868, cycle-exact framing |
| lif_vectors | icarus | PASS | 0.3 | PASS tb_lif: 9561 vectors on lif_update and lif_pipe (58 exact-threshold firings) |
| world_random | icarus | PASS | 0.7 | PASS tb_fly_world: 6000 steps with random output spikes match the model (eaten=21 caught=8 jumps=91, 5 catches at a window end) |
| mvu_serial | icarus | PASS | 14.9 | PASS tb_mvu [serial]: 86 cases, 800 stall cycles observed |
| mvu_4x4_banked_wbuf2 | icarus | PASS | 29.4 | PASS tb_mvu [systolic 4x4 banked=1 wbuf=2]: 86 cases, 792 stall cycles observed |
| mvu_4x4_banked_wbuf1 | icarus | PASS | 34.5 | PASS tb_mvu [systolic 4x4 banked=1 wbuf=1]: 86 cases, 1025 stall cycles observed |
| mvu_4x4_simple_wbuf1 | icarus | PASS | 42.5 | PASS tb_mvu [systolic 4x4 banked=0 wbuf=1]: 86 cases, 925 stall cycles observed |
| mvu_4x4_banked_wbuf3 | icarus | PASS | 30.0 | PASS tb_mvu [systolic 4x4 banked=1 wbuf=3]: 86 cases, 795 stall cycles observed |
| mvu_2x2_banked_wbuf2 | icarus | PASS | 21.9 | PASS tb_mvu [systolic 2x2 banked=1 wbuf=2]: 86 cases, 946 stall cycles observed |
| mvu_2x2_simple_wbuf1 | icarus | PASS | 29.1 | PASS tb_mvu [systolic 2x2 banked=0 wbuf=1]: 86 cases, 919 stall cycles observed |
| mvu_2x8_banked_wbuf2 | icarus | PASS | 28.4 | PASS tb_mvu [systolic 2x8 banked=1 wbuf=2]: 86 cases, 885 stall cycles observed |
| mvu_8x8_banked_wbuf2 | icarus | PASS | 77.3 | PASS tb_mvu [systolic 8x8 banked=1 wbuf=2]: 86 cases, 904 stall cycles observed |
| mvu_1x1_simple_wbuf1 | icarus | PASS | 33.0 | PASS tb_mvu [systolic 1x1 banked=0 wbuf=1]: 86 cases, 909 stall cycles observed |
| fly_core_serial | icarus | PASS | 215.0 | PASS tb_fly_core [serial]: 44 steps match the reference model (318 spikes, eaten=1 caught=0) |
| fly_core_4x4_banked_wbuf2 | icarus | PASS | 158.3 | PASS tb_fly_core [systolic 4x4 banked=1 wbuf=2]: 44 steps match the reference model (318 spikes, eaten=1 caught=0) |
| sva_mvu_serial | verilator | PASS | 15.0 | PASS tb_mvu [serial]: 86 cases, 800 stall cycles observed |
| sva_mvu_4x4_banked_wbuf2 | verilator | PASS | 12.4 | PASS tb_mvu [systolic 4x4 banked=1 wbuf=2]: 86 cases, 792 stall cycles observed |
| sva_mvu_2x8_banked_wbuf2 | verilator | PASS | 12.0 | PASS tb_mvu [systolic 2x8 banked=1 wbuf=2]: 86 cases, 885 stall cycles observed |
| sva_mvu_4x4_simple_wbuf1 | verilator | PASS | 12.8 | PASS tb_mvu [systolic 4x4 banked=0 wbuf=1]: 86 cases, 925 stall cycles observed |
| sva_fly_core_4x4_banked_wbuf2 | verilator | PASS | 28.8 | PASS tb_fly_core [systolic 4x4 banked=1 wbuf=2]: 700 steps match the reference model (1877 spikes, eaten=5 caught=2) |
| sva_fly_core_serial | verilator | PASS | 39.9 | PASS tb_fly_core [serial]: 700 steps match the reference model (1877 spikes, eaten=5 caught=2) |
| sva_fly_core_2x2_banked_wbuf2 | verilator | PASS | 49.1 | PASS tb_fly_core [systolic 2x2 banked=1 wbuf=2]: 700 steps match the reference model (1877 spikes, eaten=5 caught=2) |
| sva_fly_core_4x4_simple_wbuf1 | verilator | PASS | 87.4 | PASS tb_fly_core [systolic 4x4 banked=0 wbuf=1]: 700 steps match the reference model (1877 spikes, eaten=5 caught=2) |
| sva_fly_core_8x8_banked_wbuf2 | verilator | PASS | 31.0 | PASS tb_fly_core [systolic 8x8 banked=1 wbuf=2]: 700 steps match the reference model (1877 spikes, eaten=5 caught=2) |
| telemetry_e2e_nodrop | verilator | PASS | 48.8 | PASS check_telemetry: 527 packets, steps 0..700, 0 dropped snapshots, all fields match the model |
| telemetry_e2e_drops | verilator | PASS | 50.5 | PASS check_telemetry: 716 packets, steps 0..700, 6308 dropped snapshots, all fields match the model |
| basys3_top_smoke | verilator | PASS | 16.6 | PASS check_top_state: step 63, rtl (39, 35, 1, 8, 12, 0, 4139), model (39, 35, 1, 8, 12, 0, 4139) / PASS check_stream: 93 packets, crc_err=0 hdr_err=0 seq_gaps=0 resets=1 steps 0..63 |
| mutant_pe_zero_extend | mvu_4x4 | PASS | 1.0 | product zero-extended instead of sign-extended -> FAIL case 1 dim 64: y[12] expected -2, got 65534 |
| mutant_serial_unsigned | mvu_serial | PASS | 0.5 | serial multiply without signed casts -> FAIL case 1 dim 64: y[12] expected -2, got 254 |
| mutant_weight_src_mask | mvu_4x4 | PASS | 1.1 | partial-tile source mask removed -> FAIL case 2 dim 5: y[0] expected -122, got -19754 |
| mutant_stale_accumulator | mvu_4x4 | PASS | 0.5 | accumulator not restarted per output group -> FAIL case 0 dim 64: y[0] expected 0, got x |
| mutant_buffer_hazard_wide | mvu_2x8 | PASS | 0.6 | weight-buffer hazard check removed (wide array, result checks) -> FAIL case 1 dim 64: y[2] expected 107, got 0 |
| mutant_buffer_hazard_sva | sva_mvu_4x4 | PASS | 12.0 | weight-buffer hazard check removed (square array, assertions) -> [41745000] %Error: mvu_sva.sv:136: Assertion failed in TOP.tb_mvu.g_dut.dut.u_sys_sva.a_busy_count: buffer bookkeeping |
| mutant_skew_valid | mvu_4x4 | PASS | 5.6 | input skew of valid bits wrong ->        Time: 1041646000  Scope: tb_mvu.run_cmd |
| mutant_ignore_backpressure | mvu_4x4 | PASS | 10.6 | result stream ignores res_ready -> FAIL [1664665000] output changed while stalled |
| mutant_write_while_busy | mvu_4x4 | PASS | 30.6 | weight writes accepted while busy -> FAIL [41655000] ready asserted while busy |
| mutant_loader_not_reset | mvu_4x4 | PASS | 16.0 | loader state survives reset -> FAIL case 49 dim 64: y[0] expected -23493, got 3560 |
| mutant_lif_strict_gt | lif | PASS | 0.0 | fires on > instead of >= -> FAIL th=100 v=0 i=100 u=0: got (100,0) expected (0,1) |
| mutant_lif_no_clamp | lif | PASS | 0.0 | negative candidate not clamped to 0 -> FAIL th=100 v=0 i=-1 u=0: got (65535,0) expected (0,0) |
| mutant_lif_pipe_tag_skew | lif | PASS | 0.0 | pipelined LIF result written to the wrong neuron -> FAIL lif_pipe vector 1: got (0,1) expected (99,0) |
| mutant_same_step_contamination | fly_core | PASS | 6.8 | LIF reads the next bank instead of the current bank -> FAIL step 42 (systolic 4x4 banked=1 wbuf=2) |
| mutant_commit_incomplete | sva_fly_core | PASS | 6.2 | commit before the last neuron -> [944775000] %Error: fly_sva.sv:23: Assertion failed in TOP.tb_fly_core.dut.u_core_sva.a_commit_complete: commit before all 256 neurons written |
| mutant_sensor_input_shift | fly_core | PASS | 6.8 | sensor drive applied to the wrong neurons -> FAIL step 41: V[4] rtl=0 model=60 |
| mutant_world_threat_side_flipped | fly_core | PASS | 9.8 | looming input sent to the wrong side -> FAIL step 142: V[16] rtl=0 model=60 |
| mutant_world_steer_reversed | fly_core | PASS | 20.0 | steering neurons turn the fly the wrong way -> FAIL step 456 (systolic 4x4 banked=1 wbuf=2) |
| mutant_world_threat_period | fly_core | PASS | 10.4 | threat pursues at the wrong rate -> FAIL step 160 (systolic 4x4 banked=1 wbuf=2) |
| mutant_world_catch_before_pursuit | world | PASS | 0.2 | catch check skipped after a motor window -> FAIL step 2184 |
| mutant_world_jump_toward_threat | world | PASS | 0.1 | escape jump heads toward the threat -> FAIL step 624 |
| mutant_world_back_margin | world | PASS | 0.0 | backing-up threshold off by one -> FAIL step 216 |
| mutant_world_food_ahead_axis | world | PASS | 0.0 | food button places food on the wrong axis -> FAIL step 66 |
| mutant_world_jump_no_retry | fly_core | PASS | 14.3 | jump gives up at a wall instead of trying other headings -> FAIL step 304 (systolic 4x4 banked=1 wbuf=2) |
| mutant_uart_lsb_msb | uart | PASS | 0.0 | data sent MSB first ->        Time: 6646000  Scope: tb_uart_tx.expect_frame |
| mutant_telemetry_no_clear | telemetry | PASS | 20.4 | activity counters not cleared at capture -> FAIL: seq 33 step 43: activity mismatch (prev step 42) |
| mutant_crc_init | telemetry | PASS | 20.3 | CRC initial value wrong -> FAIL: parser stats crc=153 hdr=0 discarded=18207 gaps=0 |

## Cycle counts (simulation, no output stalls)

```
mvu_serial: PERF case=0 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=1 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=2 dim=5 stall=0 cycles=34
mvu_serial: PERF case=3 dim=5 stall=0 cycles=34
mvu_serial: PERF case=4 dim=5 stall=0 cycles=34
mvu_serial: PERF case=5 dim=7 stall=0 cycles=60
mvu_serial: PERF case=6 dim=7 stall=0 cycles=60
mvu_serial: PERF case=7 dim=7 stall=0 cycles=60
mvu_serial: PERF case=8 dim=7 stall=0 cycles=60
mvu_serial: PERF case=9 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=10 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=11 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=12 dim=33 stall=0 cycles=1126
mvu_serial: PERF case=13 dim=33 stall=0 cycles=1126
mvu_serial: PERF case=14 dim=1 stall=0 cycles=6
mvu_serial: PERF case=15 dim=2 stall=0 cycles=10
mvu_serial: PERF case=16 dim=3 stall=0 cycles=16
mvu_serial: PERF case=17 dim=4 stall=0 cycles=24
mvu_serial: PERF case=18 dim=5 stall=0 cycles=34
mvu_serial: PERF case=19 dim=7 stall=0 cycles=60
mvu_serial: PERF case=20 dim=8 stall=0 cycles=76
mvu_serial: PERF case=21 dim=9 stall=0 cycles=94
mvu_serial: PERF case=22 dim=16 stall=0 cycles=276
mvu_serial: PERF case=23 dim=17 stall=0 cycles=310
mvu_serial: PERF case=24 dim=31 stall=0 cycles=996
mvu_serial: PERF case=25 dim=33 stall=0 cycles=1126
mvu_serial: PERF case=26 dim=63 stall=0 cycles=4036
mvu_serial: PERF case=27 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=28 dim=0 stall=0 cycles=1
mvu_serial: PERF case=29 dim=65 stall=0 cycles=1
mvu_serial: PERF case=30 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=31 dim=5 stall=0 cycles=34
mvu_serial: PERF case=32 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=33 dim=1 stall=0 cycles=6
mvu_serial: PERF case=34 dim=63 stall=0 cycles=4036
mvu_serial: PERF case=35 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=36 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=37 dim=13 stall=0 cycles=186
mvu_serial: PERF case=38 dim=64 stall=50 cycles=4255
mvu_serial: PERF case=39 dim=5 stall=80 cycles=53
mvu_serial: PERF case=40 dim=17 stall=90 cycles=439
mvu_serial: PERF case=41 dim=1 stall=95 cycles=8
mvu_serial: PERF case=42 dim=63 stall=30 cycles=4063
mvu_serial: PERF case=43 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=56 dim=4 stall=60 cycles=35
mvu_serial: PERF case=57 dim=36 stall=60 cycles=1384
mvu_serial: PERF case=58 dim=4 stall=0 cycles=24
mvu_serial: PERF case=59 dim=3 stall=0 cycles=16
mvu_serial: PERF case=60 dim=13 stall=0 cycles=186
mvu_serial: PERF case=61 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=62 dim=64 stall=0 cycles=4164
mvu_serial: PERF case=63 dim=46 stall=0 cycles=2166
mvu_serial: PERF case=64 dim=5 stall=0 cycles=34
mvu_serial: PERF case=65 dim=42 stall=25 cycles=1820
mvu_serial: PERF case=66 dim=23 stall=0 cycles=556
mvu_serial: PERF case=67 dim=24 stall=60 cycles=633
mvu_serial: PERF case=68 dim=3 stall=60 cycles=17
mvu_serial: PERF case=69 dim=5 stall=0 cycles=34
mvu_serial: PERF case=70 dim=5 stall=0 cycles=34
mvu_serial: PERF case=71 dim=5 stall=25 cycles=36
mvu_serial: PERF case=72 dim=12 stall=0 cycles=160
mvu_serial: PERF case=73 dim=54 stall=0 cycles=2974
mvu_serial: PERF case=74 dim=49 stall=0 cycles=2454
mvu_serial: PERF case=75 dim=63 stall=0 cycles=4036
mvu_serial: PERF case=76 dim=13 stall=60 cycles=198
mvu_serial: PERF case=77 dim=64 stall=60 cycles=4242
mvu_serial: PERF case=78 dim=63 stall=0 cycles=4036
mvu_serial: PERF case=79 dim=14 stall=60 cycles=229
mvu_serial: PERF case=80 dim=5 stall=25 cycles=37
mvu_serial: PERF case=81 dim=3 stall=25 cycles=16
mvu_serial: PERF case=82 dim=4 stall=25 cycles=24
mvu_serial: PERF case=83 dim=41 stall=60 cycles=1782
mvu_serial: PERF case=84 dim=1 stall=0 cycles=6
mvu_serial: PERF case=85 dim=40 stall=60 cycles=1690
mvu_4x4_banked_wbuf2: PERF case=0 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=1 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=2 dim=5 stall=0 cycles=38
mvu_4x4_banked_wbuf2: PERF case=3 dim=5 stall=0 cycles=38
mvu_4x4_banked_wbuf2: PERF case=4 dim=5 stall=0 cycles=38
mvu_4x4_banked_wbuf2: PERF case=5 dim=7 stall=0 cycles=40
mvu_4x4_banked_wbuf2: PERF case=6 dim=7 stall=0 cycles=40
mvu_4x4_banked_wbuf2: PERF case=7 dim=7 stall=0 cycles=40
mvu_4x4_banked_wbuf2: PERF case=8 dim=7 stall=0 cycles=40
mvu_4x4_banked_wbuf2: PERF case=9 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=10 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=11 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=12 dim=33 stall=0 cycles=608
mvu_4x4_banked_wbuf2: PERF case=13 dim=33 stall=0 cycles=608
mvu_4x4_banked_wbuf2: PERF case=14 dim=1 stall=0 cycles=16
mvu_4x4_banked_wbuf2: PERF case=15 dim=2 stall=0 cycles=17
mvu_4x4_banked_wbuf2: PERF case=16 dim=3 stall=0 cycles=18
mvu_4x4_banked_wbuf2: PERF case=17 dim=4 stall=0 cycles=19
mvu_4x4_banked_wbuf2: PERF case=18 dim=5 stall=0 cycles=38
mvu_4x4_banked_wbuf2: PERF case=19 dim=7 stall=0 cycles=40
mvu_4x4_banked_wbuf2: PERF case=20 dim=8 stall=0 cycles=41
mvu_4x4_banked_wbuf2: PERF case=21 dim=9 stall=0 cycles=80
mvu_4x4_banked_wbuf2: PERF case=22 dim=16 stall=0 cycles=133
mvu_4x4_banked_wbuf2: PERF case=23 dim=17 stall=0 cycles=200
mvu_4x4_banked_wbuf2: PERF case=24 dim=31 stall=0 cycles=484
mvu_4x4_banked_wbuf2: PERF case=25 dim=33 stall=0 cycles=608
mvu_4x4_banked_wbuf2: PERF case=26 dim=63 stall=0 cycles=1860
mvu_4x4_banked_wbuf2: PERF case=27 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=28 dim=0 stall=0 cycles=1
mvu_4x4_banked_wbuf2: PERF case=29 dim=65 stall=0 cycles=1
mvu_4x4_banked_wbuf2: PERF case=30 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=31 dim=5 stall=0 cycles=38
mvu_4x4_banked_wbuf2: PERF case=32 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=33 dim=1 stall=0 cycles=16
mvu_4x4_banked_wbuf2: PERF case=34 dim=63 stall=0 cycles=1860
mvu_4x4_banked_wbuf2: PERF case=35 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=36 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=37 dim=13 stall=0 cycles=130
mvu_4x4_banked_wbuf2: PERF case=38 dim=64 stall=50 cycles=1929
mvu_4x4_banked_wbuf2: PERF case=39 dim=5 stall=80 cycles=55
mvu_4x4_banked_wbuf2: PERF case=40 dim=17 stall=90 cycles=304
mvu_4x4_banked_wbuf2: PERF case=41 dim=1 stall=95 cycles=19
mvu_4x4_banked_wbuf2: PERF case=42 dim=63 stall=30 cycles=1893
mvu_4x4_banked_wbuf2: PERF case=43 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=56 dim=4 stall=60 cycles=25
mvu_4x4_banked_wbuf2: PERF case=57 dim=36 stall=60 cycles=646
mvu_4x4_banked_wbuf2: PERF case=58 dim=4 stall=0 cycles=19
mvu_4x4_banked_wbuf2: PERF case=59 dim=3 stall=0 cycles=18
mvu_4x4_banked_wbuf2: PERF case=60 dim=13 stall=0 cycles=130
mvu_4x4_banked_wbuf2: PERF case=61 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=62 dim=64 stall=0 cycles=1861
mvu_4x4_banked_wbuf2: PERF case=63 dim=46 stall=0 cycles=1059
mvu_4x4_banked_wbuf2: PERF case=64 dim=5 stall=0 cycles=38
mvu_4x4_banked_wbuf2: PERF case=65 dim=42 stall=25 cycles=904
mvu_4x4_banked_wbuf2: PERF case=66 dim=23 stall=0 cycles=280
mvu_4x4_banked_wbuf2: PERF case=67 dim=24 stall=60 cycles=301
mvu_4x4_banked_wbuf2: PERF case=68 dim=3 stall=60 cycles=21
mvu_4x4_banked_wbuf2: PERF case=69 dim=5 stall=0 cycles=38
mvu_4x4_banked_wbuf2: PERF case=70 dim=5 stall=0 cycles=38
mvu_4x4_banked_wbuf2: PERF case=71 dim=5 stall=25 cycles=38
mvu_4x4_banked_wbuf2: PERF case=72 dim=12 stall=0 cycles=83
mvu_4x4_banked_wbuf2: PERF case=73 dim=54 stall=0 cycles=1431
mvu_4x4_banked_wbuf2: PERF case=74 dim=49 stall=0 cycles=1240
mvu_4x4_banked_wbuf2: PERF case=75 dim=63 stall=0 cycles=1860
mvu_4x4_banked_wbuf2: PERF case=76 dim=13 stall=60 cycles=158
mvu_4x4_banked_wbuf2: PERF case=77 dim=64 stall=60 cycles=1946
mvu_4x4_banked_wbuf2: PERF case=78 dim=63 stall=0 cycles=1860
mvu_4x4_banked_wbuf2: PERF case=79 dim=14 stall=60 cycles=148
mvu_4x4_banked_wbuf2: PERF case=80 dim=5 stall=25 cycles=40
mvu_4x4_banked_wbuf2: PERF case=81 dim=3 stall=25 cycles=22
mvu_4x4_banked_wbuf2: PERF case=82 dim=4 stall=25 cycles=19
mvu_4x4_banked_wbuf2: PERF case=83 dim=41 stall=60 cycles=960
mvu_4x4_banked_wbuf2: PERF case=84 dim=1 stall=0 cycles=16
mvu_4x4_banked_wbuf2: PERF case=85 dim=40 stall=60 cycles=808
mvu_4x4_banked_wbuf1: PERF case=0 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=1 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=2 dim=5 stall=0 cycles=62
mvu_4x4_banked_wbuf1: PERF case=3 dim=5 stall=0 cycles=62
mvu_4x4_banked_wbuf1: PERF case=4 dim=5 stall=0 cycles=62
mvu_4x4_banked_wbuf1: PERF case=5 dim=7 stall=0 cycles=64
mvu_4x4_banked_wbuf1: PERF case=6 dim=7 stall=0 cycles=64
mvu_4x4_banked_wbuf1: PERF case=7 dim=7 stall=0 cycles=64
mvu_4x4_banked_wbuf1: PERF case=8 dim=7 stall=0 cycles=64
mvu_4x4_banked_wbuf1: PERF case=9 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=10 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=11 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=12 dim=33 stall=0 cycles=1168
mvu_4x4_banked_wbuf1: PERF case=13 dim=33 stall=0 cycles=1168
mvu_4x4_banked_wbuf1: PERF case=14 dim=1 stall=0 cycles=16
mvu_4x4_banked_wbuf1: PERF case=15 dim=2 stall=0 cycles=17
mvu_4x4_banked_wbuf1: PERF case=16 dim=3 stall=0 cycles=18
mvu_4x4_banked_wbuf1: PERF case=17 dim=4 stall=0 cycles=19
mvu_4x4_banked_wbuf1: PERF case=18 dim=5 stall=0 cycles=62
mvu_4x4_banked_wbuf1: PERF case=19 dim=7 stall=0 cycles=64
mvu_4x4_banked_wbuf1: PERF case=20 dim=8 stall=0 cycles=65
mvu_4x4_banked_wbuf1: PERF case=21 dim=9 stall=0 cycles=136
mvu_4x4_banked_wbuf1: PERF case=22 dim=16 stall=0 cycles=241
mvu_4x4_banked_wbuf1: PERF case=23 dim=17 stall=0 cycles=368
mvu_4x4_banked_wbuf1: PERF case=24 dim=31 stall=0 cycles=928
mvu_4x4_banked_wbuf1: PERF case=25 dim=33 stall=0 cycles=1168
mvu_4x4_banked_wbuf1: PERF case=26 dim=63 stall=0 cycles=3648
mvu_4x4_banked_wbuf1: PERF case=27 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=28 dim=0 stall=0 cycles=1
mvu_4x4_banked_wbuf1: PERF case=29 dim=65 stall=0 cycles=1
mvu_4x4_banked_wbuf1: PERF case=30 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=31 dim=5 stall=0 cycles=62
mvu_4x4_banked_wbuf1: PERF case=32 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=33 dim=1 stall=0 cycles=16
mvu_4x4_banked_wbuf1: PERF case=34 dim=63 stall=0 cycles=3648
mvu_4x4_banked_wbuf1: PERF case=35 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=36 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=37 dim=13 stall=0 cycles=238
mvu_4x4_banked_wbuf1: PERF case=38 dim=64 stall=50 cycles=3706
mvu_4x4_banked_wbuf1: PERF case=39 dim=5 stall=80 cycles=109
mvu_4x4_banked_wbuf1: PERF case=40 dim=17 stall=90 cycles=619
mvu_4x4_banked_wbuf1: PERF case=41 dim=1 stall=95 cycles=23
mvu_4x4_banked_wbuf1: PERF case=42 dim=63 stall=30 cycles=3689
mvu_4x4_banked_wbuf1: PERF case=43 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=56 dim=4 stall=60 cycles=26
mvu_4x4_banked_wbuf1: PERF case=57 dim=36 stall=60 cycles=1212
mvu_4x4_banked_wbuf1: PERF case=58 dim=4 stall=0 cycles=19
mvu_4x4_banked_wbuf1: PERF case=59 dim=3 stall=0 cycles=18
mvu_4x4_banked_wbuf1: PERF case=60 dim=13 stall=0 cycles=238
mvu_4x4_banked_wbuf1: PERF case=61 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=62 dim=64 stall=0 cycles=3649
mvu_4x4_banked_wbuf1: PERF case=63 dim=46 stall=0 cycles=2063
mvu_4x4_banked_wbuf1: PERF case=64 dim=5 stall=0 cycles=62
mvu_4x4_banked_wbuf1: PERF case=65 dim=42 stall=25 cycles=1752
mvu_4x4_banked_wbuf1: PERF case=66 dim=23 stall=0 cycles=528
mvu_4x4_banked_wbuf1: PERF case=67 dim=24 stall=60 cycles=567
mvu_4x4_banked_wbuf1: PERF case=68 dim=3 stall=60 cycles=20
mvu_4x4_banked_wbuf1: PERF case=69 dim=5 stall=0 cycles=62
mvu_4x4_banked_wbuf1: PERF case=70 dim=5 stall=0 cycles=62
mvu_4x4_banked_wbuf1: PERF case=71 dim=5 stall=25 cycles=67
mvu_4x4_banked_wbuf1: PERF case=72 dim=12 stall=0 cycles=139
mvu_4x4_banked_wbuf1: PERF case=73 dim=54 stall=0 cycles=2799
mvu_4x4_banked_wbuf1: PERF case=74 dim=49 stall=0 cycles=2416
mvu_4x4_banked_wbuf1: PERF case=75 dim=63 stall=0 cycles=3648
mvu_4x4_banked_wbuf1: PERF case=76 dim=13 stall=60 cycles=264
mvu_4x4_banked_wbuf1: PERF case=77 dim=64 stall=60 cycles=3747
mvu_4x4_banked_wbuf1: PERF case=78 dim=63 stall=0 cycles=3648
mvu_4x4_banked_wbuf1: PERF case=79 dim=14 stall=60 cycles=266
mvu_4x4_banked_wbuf1: PERF case=80 dim=5 stall=25 cycles=63
mvu_4x4_banked_wbuf1: PERF case=81 dim=3 stall=25 cycles=18
mvu_4x4_banked_wbuf1: PERF case=82 dim=4 stall=25 cycles=20
mvu_4x4_banked_wbuf1: PERF case=83 dim=41 stall=60 cycles=1797
mvu_4x4_banked_wbuf1: PERF case=84 dim=1 stall=0 cycles=16
mvu_4x4_banked_wbuf1: PERF case=85 dim=40 stall=60 cycles=1514
mvu_4x4_simple_wbuf1: PERF case=0 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=1 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=2 dim=5 stall=0 cycles=110
mvu_4x4_simple_wbuf1: PERF case=3 dim=5 stall=0 cycles=110
mvu_4x4_simple_wbuf1: PERF case=4 dim=5 stall=0 cycles=110
mvu_4x4_simple_wbuf1: PERF case=5 dim=7 stall=0 cycles=112
mvu_4x4_simple_wbuf1: PERF case=6 dim=7 stall=0 cycles=112
mvu_4x4_simple_wbuf1: PERF case=7 dim=7 stall=0 cycles=112
mvu_4x4_simple_wbuf1: PERF case=8 dim=7 stall=0 cycles=112
mvu_4x4_simple_wbuf1: PERF case=9 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=10 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=11 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=12 dim=33 stall=0 cycles=2140
mvu_4x4_simple_wbuf1: PERF case=13 dim=33 stall=0 cycles=2140
mvu_4x4_simple_wbuf1: PERF case=14 dim=1 stall=0 cycles=28
mvu_4x4_simple_wbuf1: PERF case=15 dim=2 stall=0 cycles=29
mvu_4x4_simple_wbuf1: PERF case=16 dim=3 stall=0 cycles=30
mvu_4x4_simple_wbuf1: PERF case=17 dim=4 stall=0 cycles=31
mvu_4x4_simple_wbuf1: PERF case=18 dim=5 stall=0 cycles=110
mvu_4x4_simple_wbuf1: PERF case=19 dim=7 stall=0 cycles=112
mvu_4x4_simple_wbuf1: PERF case=20 dim=8 stall=0 cycles=113
mvu_4x4_simple_wbuf1: PERF case=21 dim=9 stall=0 cycles=244
mvu_4x4_simple_wbuf1: PERF case=22 dim=16 stall=0 cycles=433
mvu_4x4_simple_wbuf1: PERF case=23 dim=17 stall=0 cycles=668
mvu_4x4_simple_wbuf1: PERF case=24 dim=31 stall=0 cycles=1696
mvu_4x4_simple_wbuf1: PERF case=25 dim=33 stall=0 cycles=2140
mvu_4x4_simple_wbuf1: PERF case=26 dim=63 stall=0 cycles=6720
mvu_4x4_simple_wbuf1: PERF case=27 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=28 dim=0 stall=0 cycles=1
mvu_4x4_simple_wbuf1: PERF case=29 dim=65 stall=0 cycles=1
mvu_4x4_simple_wbuf1: PERF case=30 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=31 dim=5 stall=0 cycles=110
mvu_4x4_simple_wbuf1: PERF case=32 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=33 dim=1 stall=0 cycles=28
mvu_4x4_simple_wbuf1: PERF case=34 dim=63 stall=0 cycles=6720
mvu_4x4_simple_wbuf1: PERF case=35 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=36 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=37 dim=13 stall=0 cycles=430
mvu_4x4_simple_wbuf1: PERF case=38 dim=64 stall=50 cycles=6805
mvu_4x4_simple_wbuf1: PERF case=39 dim=5 stall=80 cycles=115
mvu_4x4_simple_wbuf1: PERF case=40 dim=17 stall=90 cycles=848
mvu_4x4_simple_wbuf1: PERF case=41 dim=1 stall=95 cycles=41
mvu_4x4_simple_wbuf1: PERF case=42 dim=63 stall=30 cycles=6755
mvu_4x4_simple_wbuf1: PERF case=43 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=56 dim=4 stall=60 cycles=44
mvu_4x4_simple_wbuf1: PERF case=57 dim=36 stall=60 cycles=2208
mvu_4x4_simple_wbuf1: PERF case=58 dim=4 stall=0 cycles=31
mvu_4x4_simple_wbuf1: PERF case=59 dim=3 stall=0 cycles=30
mvu_4x4_simple_wbuf1: PERF case=60 dim=13 stall=0 cycles=430
mvu_4x4_simple_wbuf1: PERF case=61 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=62 dim=64 stall=0 cycles=6721
mvu_4x4_simple_wbuf1: PERF case=63 dim=46 stall=0 cycles=3791
mvu_4x4_simple_wbuf1: PERF case=64 dim=5 stall=0 cycles=110
mvu_4x4_simple_wbuf1: PERF case=65 dim=42 stall=25 cycles=3201
mvu_4x4_simple_wbuf1: PERF case=66 dim=23 stall=0 cycles=960
mvu_4x4_simple_wbuf1: PERF case=67 dim=24 stall=60 cycles=1003
mvu_4x4_simple_wbuf1: PERF case=68 dim=3 stall=60 cycles=34
mvu_4x4_simple_wbuf1: PERF case=69 dim=5 stall=0 cycles=110
mvu_4x4_simple_wbuf1: PERF case=70 dim=5 stall=0 cycles=110
mvu_4x4_simple_wbuf1: PERF case=71 dim=5 stall=25 cycles=111
mvu_4x4_simple_wbuf1: PERF case=72 dim=12 stall=0 cycles=247
mvu_4x4_simple_wbuf1: PERF case=73 dim=54 stall=0 cycles=5151
mvu_4x4_simple_wbuf1: PERF case=74 dim=49 stall=0 cycles=4444
mvu_4x4_simple_wbuf1: PERF case=75 dim=63 stall=0 cycles=6720
mvu_4x4_simple_wbuf1: PERF case=76 dim=13 stall=60 cycles=453
mvu_4x4_simple_wbuf1: PERF case=77 dim=64 stall=60 cycles=6821
mvu_4x4_simple_wbuf1: PERF case=78 dim=63 stall=0 cycles=6720
mvu_4x4_simple_wbuf1: PERF case=79 dim=14 stall=60 cycles=452
mvu_4x4_simple_wbuf1: PERF case=80 dim=5 stall=25 cycles=116
mvu_4x4_simple_wbuf1: PERF case=81 dim=3 stall=25 cycles=32
mvu_4x4_simple_wbuf1: PERF case=82 dim=4 stall=25 cycles=32
mvu_4x4_simple_wbuf1: PERF case=83 dim=41 stall=60 cycles=3247
mvu_4x4_simple_wbuf1: PERF case=84 dim=1 stall=0 cycles=28
mvu_4x4_simple_wbuf1: PERF case=85 dim=40 stall=60 cycles=2696
mvu_4x4_banked_wbuf3: PERF case=0 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=1 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=2 dim=5 stall=0 cycles=34
mvu_4x4_banked_wbuf3: PERF case=3 dim=5 stall=0 cycles=34
mvu_4x4_banked_wbuf3: PERF case=4 dim=5 stall=0 cycles=34
mvu_4x4_banked_wbuf3: PERF case=5 dim=7 stall=0 cycles=36
mvu_4x4_banked_wbuf3: PERF case=6 dim=7 stall=0 cycles=36
mvu_4x4_banked_wbuf3: PERF case=7 dim=7 stall=0 cycles=36
mvu_4x4_banked_wbuf3: PERF case=8 dim=7 stall=0 cycles=36
mvu_4x4_banked_wbuf3: PERF case=9 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=10 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=11 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=12 dim=33 stall=0 cycles=420
mvu_4x4_banked_wbuf3: PERF case=13 dim=33 stall=0 cycles=420
mvu_4x4_banked_wbuf3: PERF case=14 dim=1 stall=0 cycles=16
mvu_4x4_banked_wbuf3: PERF case=15 dim=2 stall=0 cycles=17
mvu_4x4_banked_wbuf3: PERF case=16 dim=3 stall=0 cycles=18
mvu_4x4_banked_wbuf3: PERF case=17 dim=4 stall=0 cycles=19
mvu_4x4_banked_wbuf3: PERF case=18 dim=5 stall=0 cycles=34
mvu_4x4_banked_wbuf3: PERF case=19 dim=7 stall=0 cycles=36
mvu_4x4_banked_wbuf3: PERF case=20 dim=8 stall=0 cycles=37
mvu_4x4_banked_wbuf3: PERF case=21 dim=9 stall=0 cycles=60
mvu_4x4_banked_wbuf3: PERF case=22 dim=16 stall=0 cycles=101
mvu_4x4_banked_wbuf3: PERF case=23 dim=17 stall=0 cycles=144
mvu_4x4_banked_wbuf3: PERF case=24 dim=31 stall=0 cycles=340
mvu_4x4_banked_wbuf3: PERF case=25 dim=33 stall=0 cycles=420
mvu_4x4_banked_wbuf3: PERF case=26 dim=63 stall=0 cycles=1268
mvu_4x4_banked_wbuf3: PERF case=27 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=28 dim=0 stall=0 cycles=1
mvu_4x4_banked_wbuf3: PERF case=29 dim=65 stall=0 cycles=1
mvu_4x4_banked_wbuf3: PERF case=30 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=31 dim=5 stall=0 cycles=34
mvu_4x4_banked_wbuf3: PERF case=32 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=33 dim=1 stall=0 cycles=16
mvu_4x4_banked_wbuf3: PERF case=34 dim=63 stall=0 cycles=1268
mvu_4x4_banked_wbuf3: PERF case=35 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=36 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=37 dim=13 stall=0 cycles=98
mvu_4x4_banked_wbuf3: PERF case=38 dim=64 stall=50 cycles=1325
mvu_4x4_banked_wbuf3: PERF case=39 dim=5 stall=80 cycles=48
mvu_4x4_banked_wbuf3: PERF case=40 dim=17 stall=90 cycles=281
mvu_4x4_banked_wbuf3: PERF case=41 dim=1 stall=95 cycles=18
mvu_4x4_banked_wbuf3: PERF case=42 dim=63 stall=30 cycles=1292
mvu_4x4_banked_wbuf3: PERF case=43 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=56 dim=4 stall=60 cycles=25
mvu_4x4_banked_wbuf3: PERF case=57 dim=36 stall=60 cycles=465
mvu_4x4_banked_wbuf3: PERF case=58 dim=4 stall=0 cycles=19
mvu_4x4_banked_wbuf3: PERF case=59 dim=3 stall=0 cycles=18
mvu_4x4_banked_wbuf3: PERF case=60 dim=13 stall=0 cycles=98
mvu_4x4_banked_wbuf3: PERF case=61 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=62 dim=64 stall=0 cycles=1269
mvu_4x4_banked_wbuf3: PERF case=63 dim=46 stall=0 cycles=727
mvu_4x4_banked_wbuf3: PERF case=64 dim=5 stall=0 cycles=34
mvu_4x4_banked_wbuf3: PERF case=65 dim=42 stall=25 cycles=628
mvu_4x4_banked_wbuf3: PERF case=66 dim=23 stall=0 cycles=200
mvu_4x4_banked_wbuf3: PERF case=67 dim=24 stall=60 cycles=228
mvu_4x4_banked_wbuf3: PERF case=68 dim=3 stall=60 cycles=21
mvu_4x4_banked_wbuf3: PERF case=69 dim=5 stall=0 cycles=34
mvu_4x4_banked_wbuf3: PERF case=70 dim=5 stall=0 cycles=34
mvu_4x4_banked_wbuf3: PERF case=71 dim=5 stall=25 cycles=35
mvu_4x4_banked_wbuf3: PERF case=72 dim=12 stall=0 cycles=63
mvu_4x4_banked_wbuf3: PERF case=73 dim=54 stall=0 cycles=979
mvu_4x4_banked_wbuf3: PERF case=74 dim=49 stall=0 cycles=848
mvu_4x4_banked_wbuf3: PERF case=75 dim=63 stall=0 cycles=1268
mvu_4x4_banked_wbuf3: PERF case=76 dim=13 stall=60 cycles=113
mvu_4x4_banked_wbuf3: PERF case=77 dim=64 stall=60 cycles=1368
mvu_4x4_banked_wbuf3: PERF case=78 dim=63 stall=0 cycles=1268
mvu_4x4_banked_wbuf3: PERF case=79 dim=14 stall=60 cycles=112
mvu_4x4_banked_wbuf3: PERF case=80 dim=5 stall=25 cycles=35
mvu_4x4_banked_wbuf3: PERF case=81 dim=3 stall=25 cycles=18
mvu_4x4_banked_wbuf3: PERF case=82 dim=4 stall=25 cycles=19
mvu_4x4_banked_wbuf3: PERF case=83 dim=41 stall=60 cycles=665
mvu_4x4_banked_wbuf3: PERF case=84 dim=1 stall=0 cycles=16
mvu_4x4_banked_wbuf3: PERF case=85 dim=40 stall=60 cycles=576
mvu_2x2_banked_wbuf2: PERF case=0 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=1 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=2 dim=5 stall=0 cycles=46
mvu_2x2_banked_wbuf2: PERF case=3 dim=5 stall=0 cycles=46
mvu_2x2_banked_wbuf2: PERF case=4 dim=5 stall=0 cycles=46
mvu_2x2_banked_wbuf2: PERF case=5 dim=7 stall=0 cycles=74
mvu_2x2_banked_wbuf2: PERF case=6 dim=7 stall=0 cycles=74
mvu_2x2_banked_wbuf2: PERF case=7 dim=7 stall=0 cycles=74
mvu_2x2_banked_wbuf2: PERF case=8 dim=7 stall=0 cycles=74
mvu_2x2_banked_wbuf2: PERF case=9 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=10 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=11 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=12 dim=33 stall=0 cycles=1194
mvu_2x2_banked_wbuf2: PERF case=13 dim=33 stall=0 cycles=1194
mvu_2x2_banked_wbuf2: PERF case=14 dim=1 stall=0 cycles=10
mvu_2x2_banked_wbuf2: PERF case=15 dim=2 stall=0 cycles=11
mvu_2x2_banked_wbuf2: PERF case=16 dim=3 stall=0 cycles=22
mvu_2x2_banked_wbuf2: PERF case=17 dim=4 stall=0 cycles=23
mvu_2x2_banked_wbuf2: PERF case=18 dim=5 stall=0 cycles=46
mvu_2x2_banked_wbuf2: PERF case=19 dim=7 stall=0 cycles=74
mvu_2x2_banked_wbuf2: PERF case=20 dim=8 stall=0 cycles=75
mvu_2x2_banked_wbuf2: PERF case=21 dim=9 stall=0 cycles=114
mvu_2x2_banked_wbuf2: PERF case=22 dim=16 stall=0 cycles=275
mvu_2x2_banked_wbuf2: PERF case=23 dim=17 stall=0 cycles=346
mvu_2x2_banked_wbuf2: PERF case=24 dim=31 stall=0 cycles=1058
mvu_2x2_banked_wbuf2: PERF case=25 dim=33 stall=0 cycles=1194
mvu_2x2_banked_wbuf2: PERF case=26 dim=63 stall=0 cycles=4162
mvu_2x2_banked_wbuf2: PERF case=27 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=28 dim=0 stall=0 cycles=1
mvu_2x2_banked_wbuf2: PERF case=29 dim=65 stall=0 cycles=1
mvu_2x2_banked_wbuf2: PERF case=30 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=31 dim=5 stall=0 cycles=46
mvu_2x2_banked_wbuf2: PERF case=32 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=33 dim=1 stall=0 cycles=10
mvu_2x2_banked_wbuf2: PERF case=34 dim=63 stall=0 cycles=4162
mvu_2x2_banked_wbuf2: PERF case=35 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=36 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=37 dim=13 stall=0 cycles=214
mvu_2x2_banked_wbuf2: PERF case=38 dim=64 stall=50 cycles=4239
mvu_2x2_banked_wbuf2: PERF case=39 dim=5 stall=80 cycles=60
mvu_2x2_banked_wbuf2: PERF case=40 dim=17 stall=90 cycles=486
mvu_2x2_banked_wbuf2: PERF case=41 dim=1 stall=95 cycles=21
mvu_2x2_banked_wbuf2: PERF case=42 dim=63 stall=30 cycles=4205
mvu_2x2_banked_wbuf2: PERF case=43 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=56 dim=4 stall=60 cycles=27
mvu_2x2_banked_wbuf2: PERF case=57 dim=36 stall=60 cycles=1395
mvu_2x2_banked_wbuf2: PERF case=58 dim=4 stall=0 cycles=23
mvu_2x2_banked_wbuf2: PERF case=59 dim=3 stall=0 cycles=22
mvu_2x2_banked_wbuf2: PERF case=60 dim=13 stall=0 cycles=214
mvu_2x2_banked_wbuf2: PERF case=61 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=62 dim=64 stall=0 cycles=4163
mvu_2x2_banked_wbuf2: PERF case=63 dim=46 stall=0 cycles=2167
mvu_2x2_banked_wbuf2: PERF case=64 dim=5 stall=0 cycles=46
mvu_2x2_banked_wbuf2: PERF case=65 dim=42 stall=25 cycles=1821
mvu_2x2_banked_wbuf2: PERF case=66 dim=23 stall=0 cycles=602
mvu_2x2_banked_wbuf2: PERF case=67 dim=24 stall=60 cycles=645
mvu_2x2_banked_wbuf2: PERF case=68 dim=3 stall=60 cycles=25
mvu_2x2_banked_wbuf2: PERF case=69 dim=5 stall=0 cycles=46
mvu_2x2_banked_wbuf2: PERF case=70 dim=5 stall=0 cycles=46
mvu_2x2_banked_wbuf2: PERF case=71 dim=5 stall=25 cycles=46
mvu_2x2_banked_wbuf2: PERF case=72 dim=12 stall=0 cycles=159
mvu_2x2_banked_wbuf2: PERF case=73 dim=54 stall=0 cycles=2975
mvu_2x2_banked_wbuf2: PERF case=74 dim=49 stall=0 cycles=2554
mvu_2x2_banked_wbuf2: PERF case=75 dim=63 stall=0 cycles=4162
mvu_2x2_banked_wbuf2: PERF case=76 dim=13 stall=60 cycles=241
mvu_2x2_banked_wbuf2: PERF case=77 dim=64 stall=60 cycles=4278
mvu_2x2_banked_wbuf2: PERF case=78 dim=63 stall=0 cycles=4162
mvu_2x2_banked_wbuf2: PERF case=79 dim=14 stall=60 cycles=228
mvu_2x2_banked_wbuf2: PERF case=80 dim=5 stall=25 cycles=48
mvu_2x2_banked_wbuf2: PERF case=81 dim=3 stall=25 cycles=23
mvu_2x2_banked_wbuf2: PERF case=82 dim=4 stall=25 cycles=25
mvu_2x2_banked_wbuf2: PERF case=83 dim=41 stall=60 cycles=1886
mvu_2x2_banked_wbuf2: PERF case=84 dim=1 stall=0 cycles=10
mvu_2x2_banked_wbuf2: PERF case=85 dim=40 stall=60 cycles=1725
mvu_2x2_simple_wbuf1: PERF case=0 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=1 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=2 dim=5 stall=0 cycles=96
mvu_2x2_simple_wbuf1: PERF case=3 dim=5 stall=0 cycles=96
mvu_2x2_simple_wbuf1: PERF case=4 dim=5 stall=0 cycles=96
mvu_2x2_simple_wbuf1: PERF case=5 dim=7 stall=0 cycles=168
mvu_2x2_simple_wbuf1: PERF case=6 dim=7 stall=0 cycles=168
mvu_2x2_simple_wbuf1: PERF case=7 dim=7 stall=0 cycles=168
mvu_2x2_simple_wbuf1: PERF case=8 dim=7 stall=0 cycles=168
mvu_2x2_simple_wbuf1: PERF case=9 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=10 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=11 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=12 dim=33 stall=0 cycles=2924
mvu_2x2_simple_wbuf1: PERF case=13 dim=33 stall=0 cycles=2924
mvu_2x2_simple_wbuf1: PERF case=14 dim=1 stall=0 cycles=12
mvu_2x2_simple_wbuf1: PERF case=15 dim=2 stall=0 cycles=13
mvu_2x2_simple_wbuf1: PERF case=16 dim=3 stall=0 cycles=44
mvu_2x2_simple_wbuf1: PERF case=17 dim=4 stall=0 cycles=45
mvu_2x2_simple_wbuf1: PERF case=18 dim=5 stall=0 cycles=96
mvu_2x2_simple_wbuf1: PERF case=19 dim=7 stall=0 cycles=168
mvu_2x2_simple_wbuf1: PERF case=20 dim=8 stall=0 cycles=169
mvu_2x2_simple_wbuf1: PERF case=21 dim=9 stall=0 cycles=260
mvu_2x2_simple_wbuf1: PERF case=22 dim=16 stall=0 cycles=657
mvu_2x2_simple_wbuf1: PERF case=23 dim=17 stall=0 cycles=828
mvu_2x2_simple_wbuf1: PERF case=24 dim=31 stall=0 cycles=2592
mvu_2x2_simple_wbuf1: PERF case=25 dim=33 stall=0 cycles=2924
mvu_2x2_simple_wbuf1: PERF case=26 dim=63 stall=0 cycles=10304
mvu_2x2_simple_wbuf1: PERF case=27 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=28 dim=0 stall=0 cycles=1
mvu_2x2_simple_wbuf1: PERF case=29 dim=65 stall=0 cycles=1
mvu_2x2_simple_wbuf1: PERF case=30 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=31 dim=5 stall=0 cycles=96
mvu_2x2_simple_wbuf1: PERF case=32 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=33 dim=1 stall=0 cycles=12
mvu_2x2_simple_wbuf1: PERF case=34 dim=63 stall=0 cycles=10304
mvu_2x2_simple_wbuf1: PERF case=35 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=36 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=37 dim=13 stall=0 cycles=504
mvu_2x2_simple_wbuf1: PERF case=38 dim=64 stall=50 cycles=10358
mvu_2x2_simple_wbuf1: PERF case=39 dim=5 stall=80 cycles=122
mvu_2x2_simple_wbuf1: PERF case=40 dim=17 stall=90 cycles=984
mvu_2x2_simple_wbuf1: PERF case=41 dim=1 stall=95 cycles=43
mvu_2x2_simple_wbuf1: PERF case=42 dim=63 stall=30 cycles=10341
mvu_2x2_simple_wbuf1: PERF case=43 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=56 dim=4 stall=60 cycles=47
mvu_2x2_simple_wbuf1: PERF case=57 dim=36 stall=60 cycles=3323
mvu_2x2_simple_wbuf1: PERF case=58 dim=4 stall=0 cycles=45
mvu_2x2_simple_wbuf1: PERF case=59 dim=3 stall=0 cycles=44
mvu_2x2_simple_wbuf1: PERF case=60 dim=13 stall=0 cycles=504
mvu_2x2_simple_wbuf1: PERF case=61 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=62 dim=64 stall=0 cycles=10305
mvu_2x2_simple_wbuf1: PERF case=63 dim=46 stall=0 cycles=5337
mvu_2x2_simple_wbuf1: PERF case=64 dim=5 stall=0 cycles=96
mvu_2x2_simple_wbuf1: PERF case=65 dim=42 stall=25 cycles=4466
mvu_2x2_simple_wbuf1: PERF case=66 dim=23 stall=0 cycles=1464
mvu_2x2_simple_wbuf1: PERF case=67 dim=24 stall=60 cycles=1510
mvu_2x2_simple_wbuf1: PERF case=68 dim=3 stall=60 cycles=47
mvu_2x2_simple_wbuf1: PERF case=69 dim=5 stall=0 cycles=96
mvu_2x2_simple_wbuf1: PERF case=70 dim=5 stall=0 cycles=96
mvu_2x2_simple_wbuf1: PERF case=71 dim=5 stall=25 cycles=97
mvu_2x2_simple_wbuf1: PERF case=72 dim=12 stall=0 cycles=373
mvu_2x2_simple_wbuf1: PERF case=73 dim=54 stall=0 cycles=7345
mvu_2x2_simple_wbuf1: PERF case=74 dim=49 stall=0 cycles=6300
mvu_2x2_simple_wbuf1: PERF case=75 dim=63 stall=0 cycles=10304
mvu_2x2_simple_wbuf1: PERF case=76 dim=13 stall=60 cycles=513
mvu_2x2_simple_wbuf1: PERF case=77 dim=64 stall=60 cycles=10449
mvu_2x2_simple_wbuf1: PERF case=78 dim=63 stall=0 cycles=10304
mvu_2x2_simple_wbuf1: PERF case=79 dim=14 stall=60 cycles=529
mvu_2x2_simple_wbuf1: PERF case=80 dim=5 stall=25 cycles=98
mvu_2x2_simple_wbuf1: PERF case=81 dim=3 stall=25 cycles=46
mvu_2x2_simple_wbuf1: PERF case=82 dim=4 stall=25 cycles=46
mvu_2x2_simple_wbuf1: PERF case=83 dim=41 stall=60 cycles=4524
mvu_2x2_simple_wbuf1: PERF case=84 dim=1 stall=0 cycles=12
mvu_2x2_simple_wbuf1: PERF case=85 dim=40 stall=60 cycles=4090
mvu_2x8_banked_wbuf2: PERF case=0 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=1 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=2 dim=5 stall=0 cycles=34
mvu_2x8_banked_wbuf2: PERF case=3 dim=5 stall=0 cycles=34
mvu_2x8_banked_wbuf2: PERF case=4 dim=5 stall=0 cycles=34
mvu_2x8_banked_wbuf2: PERF case=5 dim=7 stall=0 cycles=38
mvu_2x8_banked_wbuf2: PERF case=6 dim=7 stall=0 cycles=38
mvu_2x8_banked_wbuf2: PERF case=7 dim=7 stall=0 cycles=38
mvu_2x8_banked_wbuf2: PERF case=8 dim=7 stall=0 cycles=38
mvu_2x8_banked_wbuf2: PERF case=9 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=10 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=11 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=12 dim=33 stall=0 cycles=636
mvu_2x8_banked_wbuf2: PERF case=13 dim=33 stall=0 cycles=636
mvu_2x8_banked_wbuf2: PERF case=14 dim=1 stall=0 cycles=16
mvu_2x8_banked_wbuf2: PERF case=15 dim=2 stall=0 cycles=17
mvu_2x8_banked_wbuf2: PERF case=16 dim=3 stall=0 cycles=20
mvu_2x8_banked_wbuf2: PERF case=17 dim=4 stall=0 cycles=21
mvu_2x8_banked_wbuf2: PERF case=18 dim=5 stall=0 cycles=34
mvu_2x8_banked_wbuf2: PERF case=19 dim=7 stall=0 cycles=38
mvu_2x8_banked_wbuf2: PERF case=20 dim=8 stall=0 cycles=39
mvu_2x8_banked_wbuf2: PERF case=21 dim=9 stall=0 cycles=82
mvu_2x8_banked_wbuf2: PERF case=22 dim=16 stall=0 cycles=131
mvu_2x8_banked_wbuf2: PERF case=23 dim=17 stall=0 cycles=214
mvu_2x8_banked_wbuf2: PERF case=24 dim=31 stall=0 cycles=482
mvu_2x8_banked_wbuf2: PERF case=25 dim=33 stall=0 cycles=636
mvu_2x8_banked_wbuf2: PERF case=26 dim=63 stall=0 cycles=1858
mvu_2x8_banked_wbuf2: PERF case=27 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=28 dim=0 stall=0 cycles=1
mvu_2x8_banked_wbuf2: PERF case=29 dim=65 stall=0 cycles=1
mvu_2x8_banked_wbuf2: PERF case=30 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=31 dim=5 stall=0 cycles=34
mvu_2x8_banked_wbuf2: PERF case=32 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=33 dim=1 stall=0 cycles=16
mvu_2x8_banked_wbuf2: PERF case=34 dim=63 stall=0 cycles=1858
mvu_2x8_banked_wbuf2: PERF case=35 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=36 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=37 dim=13 stall=0 cycles=114
mvu_2x8_banked_wbuf2: PERF case=38 dim=64 stall=50 cycles=1920
mvu_2x8_banked_wbuf2: PERF case=39 dim=5 stall=80 cycles=53
mvu_2x8_banked_wbuf2: PERF case=40 dim=17 stall=90 cycles=338
mvu_2x8_banked_wbuf2: PERF case=41 dim=1 stall=95 cycles=21
mvu_2x8_banked_wbuf2: PERF case=42 dim=63 stall=30 cycles=1892
mvu_2x8_banked_wbuf2: PERF case=43 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=56 dim=4 stall=60 cycles=33
mvu_2x8_banked_wbuf2: PERF case=57 dim=36 stall=60 cycles=729
mvu_2x8_banked_wbuf2: PERF case=58 dim=4 stall=0 cycles=21
mvu_2x8_banked_wbuf2: PERF case=59 dim=3 stall=0 cycles=20
mvu_2x8_banked_wbuf2: PERF case=60 dim=13 stall=0 cycles=114
mvu_2x8_banked_wbuf2: PERF case=61 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=62 dim=64 stall=0 cycles=1859
mvu_2x8_banked_wbuf2: PERF case=63 dim=46 stall=0 cycles=1015
mvu_2x8_banked_wbuf2: PERF case=64 dim=5 stall=0 cycles=34
mvu_2x8_banked_wbuf2: PERF case=65 dim=42 stall=25 cycles=940
mvu_2x8_banked_wbuf2: PERF case=66 dim=23 stall=0 cycles=278
mvu_2x8_banked_wbuf2: PERF case=67 dim=24 stall=60 cycles=307
mvu_2x8_banked_wbuf2: PERF case=68 dim=3 stall=60 cycles=31
mvu_2x8_banked_wbuf2: PERF case=69 dim=5 stall=0 cycles=34
mvu_2x8_banked_wbuf2: PERF case=70 dim=5 stall=0 cycles=34
mvu_2x8_banked_wbuf2: PERF case=71 dim=5 stall=25 cycles=35
mvu_2x8_banked_wbuf2: PERF case=72 dim=12 stall=0 cycles=99
mvu_2x8_banked_wbuf2: PERF case=73 dim=54 stall=0 cycles=1385
mvu_2x8_banked_wbuf2: PERF case=74 dim=49 stall=0 cycles=1282
mvu_2x8_banked_wbuf2: PERF case=75 dim=63 stall=0 cycles=1858
mvu_2x8_banked_wbuf2: PERF case=76 dim=13 stall=60 cycles=137
mvu_2x8_banked_wbuf2: PERF case=77 dim=64 stall=60 cycles=1942
mvu_2x8_banked_wbuf2: PERF case=78 dim=63 stall=0 cycles=1858
mvu_2x8_banked_wbuf2: PERF case=79 dim=14 stall=60 cycles=129
mvu_2x8_banked_wbuf2: PERF case=80 dim=5 stall=25 cycles=38
mvu_2x8_banked_wbuf2: PERF case=81 dim=3 stall=25 cycles=24
mvu_2x8_banked_wbuf2: PERF case=82 dim=4 stall=25 cycles=23
mvu_2x8_banked_wbuf2: PERF case=83 dim=41 stall=60 cycles=1000
mvu_2x8_banked_wbuf2: PERF case=84 dim=1 stall=0 cycles=16
mvu_2x8_banked_wbuf2: PERF case=85 dim=40 stall=60 cycles=813
mvu_8x8_banked_wbuf2: PERF case=0 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=1 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=2 dim=5 stall=0 cycles=32
mvu_8x8_banked_wbuf2: PERF case=3 dim=5 stall=0 cycles=32
mvu_8x8_banked_wbuf2: PERF case=4 dim=5 stall=0 cycles=32
mvu_8x8_banked_wbuf2: PERF case=5 dim=7 stall=0 cycles=34
mvu_8x8_banked_wbuf2: PERF case=6 dim=7 stall=0 cycles=34
mvu_8x8_banked_wbuf2: PERF case=7 dim=7 stall=0 cycles=34
mvu_8x8_banked_wbuf2: PERF case=8 dim=7 stall=0 cycles=34
mvu_8x8_banked_wbuf2: PERF case=9 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=10 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=11 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=12 dim=33 stall=0 cycles=372
mvu_8x8_banked_wbuf2: PERF case=13 dim=33 stall=0 cycles=372
mvu_8x8_banked_wbuf2: PERF case=14 dim=1 stall=0 cycles=28
mvu_8x8_banked_wbuf2: PERF case=15 dim=2 stall=0 cycles=29
mvu_8x8_banked_wbuf2: PERF case=16 dim=3 stall=0 cycles=30
mvu_8x8_banked_wbuf2: PERF case=17 dim=4 stall=0 cycles=31
mvu_8x8_banked_wbuf2: PERF case=18 dim=5 stall=0 cycles=32
mvu_8x8_banked_wbuf2: PERF case=19 dim=7 stall=0 cycles=34
mvu_8x8_banked_wbuf2: PERF case=20 dim=8 stall=0 cycles=35
mvu_8x8_banked_wbuf2: PERF case=21 dim=9 stall=0 cycles=70
mvu_8x8_banked_wbuf2: PERF case=22 dim=16 stall=0 cycles=77
mvu_8x8_banked_wbuf2: PERF case=23 dim=17 stall=0 cycles=148
mvu_8x8_banked_wbuf2: PERF case=24 dim=31 stall=0 cycles=248
mvu_8x8_banked_wbuf2: PERF case=25 dim=33 stall=0 cycles=372
mvu_8x8_banked_wbuf2: PERF case=26 dim=63 stall=0 cycles=904
mvu_8x8_banked_wbuf2: PERF case=27 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=28 dim=0 stall=0 cycles=1
mvu_8x8_banked_wbuf2: PERF case=29 dim=65 stall=0 cycles=1
mvu_8x8_banked_wbuf2: PERF case=30 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=31 dim=5 stall=0 cycles=32
mvu_8x8_banked_wbuf2: PERF case=32 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=33 dim=1 stall=0 cycles=28
mvu_8x8_banked_wbuf2: PERF case=34 dim=63 stall=0 cycles=904
mvu_8x8_banked_wbuf2: PERF case=35 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=36 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=37 dim=13 stall=0 cycles=74
mvu_8x8_banked_wbuf2: PERF case=38 dim=64 stall=50 cycles=969
mvu_8x8_banked_wbuf2: PERF case=39 dim=5 stall=80 cycles=65
mvu_8x8_banked_wbuf2: PERF case=40 dim=17 stall=90 cycles=321
mvu_8x8_banked_wbuf2: PERF case=41 dim=1 stall=95 cycles=41
mvu_8x8_banked_wbuf2: PERF case=42 dim=63 stall=30 cycles=925
mvu_8x8_banked_wbuf2: PERF case=43 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=56 dim=4 stall=60 cycles=34
mvu_8x8_banked_wbuf2: PERF case=57 dim=36 stall=60 cycles=421
mvu_8x8_banked_wbuf2: PERF case=58 dim=4 stall=0 cycles=31
mvu_8x8_banked_wbuf2: PERF case=59 dim=3 stall=0 cycles=30
mvu_8x8_banked_wbuf2: PERF case=60 dim=13 stall=0 cycles=74
mvu_8x8_banked_wbuf2: PERF case=61 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=62 dim=64 stall=0 cycles=905
mvu_8x8_banked_wbuf2: PERF case=63 dim=46 stall=0 cycles=523
mvu_8x8_banked_wbuf2: PERF case=64 dim=5 stall=0 cycles=32
mvu_8x8_banked_wbuf2: PERF case=65 dim=42 stall=25 cycles=534
mvu_8x8_banked_wbuf2: PERF case=66 dim=23 stall=0 cycles=154
mvu_8x8_banked_wbuf2: PERF case=67 dim=24 stall=60 cycles=181
mvu_8x8_banked_wbuf2: PERF case=68 dim=3 stall=60 cycles=35
mvu_8x8_banked_wbuf2: PERF case=69 dim=5 stall=0 cycles=32
mvu_8x8_banked_wbuf2: PERF case=70 dim=5 stall=0 cycles=32
mvu_8x8_banked_wbuf2: PERF case=71 dim=5 stall=25 cycles=33
mvu_8x8_banked_wbuf2: PERF case=72 dim=12 stall=0 cycles=73
mvu_8x8_banked_wbuf2: PERF case=73 dim=54 stall=0 cycles=705
mvu_8x8_banked_wbuf2: PERF case=74 dim=49 stall=0 cycles=700
mvu_8x8_banked_wbuf2: PERF case=75 dim=63 stall=0 cycles=904
mvu_8x8_banked_wbuf2: PERF case=76 dim=13 stall=60 cycles=87
mvu_8x8_banked_wbuf2: PERF case=77 dim=64 stall=60 cycles=1003
mvu_8x8_banked_wbuf2: PERF case=78 dim=63 stall=0 cycles=904
mvu_8x8_banked_wbuf2: PERF case=79 dim=14 stall=60 cycles=97
mvu_8x8_banked_wbuf2: PERF case=80 dim=5 stall=25 cycles=34
mvu_8x8_banked_wbuf2: PERF case=81 dim=3 stall=25 cycles=30
mvu_8x8_banked_wbuf2: PERF case=82 dim=4 stall=25 cycles=34
mvu_8x8_banked_wbuf2: PERF case=83 dim=41 stall=60 cycles=573
mvu_8x8_banked_wbuf2: PERF case=84 dim=1 stall=0 cycles=28
mvu_8x8_banked_wbuf2: PERF case=85 dim=40 stall=60 cycles=432
mvu_1x1_simple_wbuf1: PERF case=0 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=1 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=2 dim=5 stall=0 cycles=131
mvu_1x1_simple_wbuf1: PERF case=3 dim=5 stall=0 cycles=131
mvu_1x1_simple_wbuf1: PERF case=4 dim=5 stall=0 cycles=131
mvu_1x1_simple_wbuf1: PERF case=5 dim=7 stall=0 cycles=253
mvu_1x1_simple_wbuf1: PERF case=6 dim=7 stall=0 cycles=253
mvu_1x1_simple_wbuf1: PERF case=7 dim=7 stall=0 cycles=253
mvu_1x1_simple_wbuf1: PERF case=8 dim=7 stall=0 cycles=253
mvu_1x1_simple_wbuf1: PERF case=9 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=10 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=11 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=12 dim=33 stall=0 cycles=5479
mvu_1x1_simple_wbuf1: PERF case=13 dim=33 stall=0 cycles=5479
mvu_1x1_simple_wbuf1: PERF case=14 dim=1 stall=0 cycles=7
mvu_1x1_simple_wbuf1: PERF case=15 dim=2 stall=0 cycles=23
mvu_1x1_simple_wbuf1: PERF case=16 dim=3 stall=0 cycles=49
mvu_1x1_simple_wbuf1: PERF case=17 dim=4 stall=0 cycles=85
mvu_1x1_simple_wbuf1: PERF case=18 dim=5 stall=0 cycles=131
mvu_1x1_simple_wbuf1: PERF case=19 dim=7 stall=0 cycles=253
mvu_1x1_simple_wbuf1: PERF case=20 dim=8 stall=0 cycles=329
mvu_1x1_simple_wbuf1: PERF case=21 dim=9 stall=0 cycles=415
mvu_1x1_simple_wbuf1: PERF case=22 dim=16 stall=0 cycles=1297
mvu_1x1_simple_wbuf1: PERF case=23 dim=17 stall=0 cycles=1463
mvu_1x1_simple_wbuf1: PERF case=24 dim=31 stall=0 cycles=4837
mvu_1x1_simple_wbuf1: PERF case=25 dim=33 stall=0 cycles=5479
mvu_1x1_simple_wbuf1: PERF case=26 dim=63 stall=0 cycles=19909
mvu_1x1_simple_wbuf1: PERF case=27 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=28 dim=0 stall=0 cycles=1
mvu_1x1_simple_wbuf1: PERF case=29 dim=65 stall=0 cycles=1
mvu_1x1_simple_wbuf1: PERF case=30 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=31 dim=5 stall=0 cycles=131
mvu_1x1_simple_wbuf1: PERF case=32 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=33 dim=1 stall=0 cycles=7
mvu_1x1_simple_wbuf1: PERF case=34 dim=63 stall=0 cycles=19909
mvu_1x1_simple_wbuf1: PERF case=35 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=36 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=37 dim=13 stall=0 cycles=859
mvu_1x1_simple_wbuf1: PERF case=38 dim=64 stall=50 cycles=20610
mvu_1x1_simple_wbuf1: PERF case=39 dim=5 stall=80 cycles=156
mvu_1x1_simple_wbuf1: PERF case=40 dim=17 stall=90 cycles=1637
mvu_1x1_simple_wbuf1: PERF case=41 dim=1 stall=95 cycles=21
mvu_1x1_simple_wbuf1: PERF case=42 dim=63 stall=30 cycles=19941
mvu_1x1_simple_wbuf1: PERF case=43 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=56 dim=4 stall=60 cycles=103
mvu_1x1_simple_wbuf1: PERF case=57 dim=36 stall=60 cycles=6557
mvu_1x1_simple_wbuf1: PERF case=58 dim=4 stall=0 cycles=85
mvu_1x1_simple_wbuf1: PERF case=59 dim=3 stall=0 cycles=49
mvu_1x1_simple_wbuf1: PERF case=60 dim=13 stall=0 cycles=859
mvu_1x1_simple_wbuf1: PERF case=61 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=62 dim=64 stall=0 cycles=20545
mvu_1x1_simple_wbuf1: PERF case=63 dim=46 stall=0 cycles=10627
mvu_1x1_simple_wbuf1: PERF case=64 dim=5 stall=0 cycles=131
mvu_1x1_simple_wbuf1: PERF case=65 dim=42 stall=25 cycles=8870
mvu_1x1_simple_wbuf1: PERF case=66 dim=23 stall=0 cycles=2669
mvu_1x1_simple_wbuf1: PERF case=67 dim=24 stall=60 cycles=2949
mvu_1x1_simple_wbuf1: PERF case=68 dim=3 stall=60 cycles=50
mvu_1x1_simple_wbuf1: PERF case=69 dim=5 stall=0 cycles=131
mvu_1x1_simple_wbuf1: PERF case=70 dim=5 stall=0 cycles=131
mvu_1x1_simple_wbuf1: PERF case=71 dim=5 stall=25 cycles=136
mvu_1x1_simple_wbuf1: PERF case=72 dim=12 stall=0 cycles=733
mvu_1x1_simple_wbuf1: PERF case=73 dim=54 stall=0 cycles=14635
mvu_1x1_simple_wbuf1: PERF case=74 dim=49 stall=0 cycles=12055
mvu_1x1_simple_wbuf1: PERF case=75 dim=63 stall=0 cycles=19909
mvu_1x1_simple_wbuf1: PERF case=76 dim=13 stall=60 cycles=871
mvu_1x1_simple_wbuf1: PERF case=77 dim=64 stall=60 cycles=20640
mvu_1x1_simple_wbuf1: PERF case=78 dim=63 stall=0 cycles=19909
mvu_1x1_simple_wbuf1: PERF case=79 dim=14 stall=60 cycles=1023
mvu_1x1_simple_wbuf1: PERF case=80 dim=5 stall=25 cycles=135
mvu_1x1_simple_wbuf1: PERF case=81 dim=3 stall=25 cycles=49
mvu_1x1_simple_wbuf1: PERF case=82 dim=4 stall=25 cycles=85
mvu_1x1_simple_wbuf1: PERF case=83 dim=41 stall=60 cycles=8505
mvu_1x1_simple_wbuf1: PERF case=84 dim=1 stall=0 cycles=7
mvu_1x1_simple_wbuf1: PERF case=85 dim=40 stall=60 cycles=8093
fly_core_serial: PERF neural_update [serial] cycles_min=65800 cycles_max=65800
fly_core_4x4_banked_wbuf2: PERF neural_update [systolic 4x4 banked=1 wbuf=2] cycles_min=28937 cycles_max=28937
fly_core_4x4_banked_wbuf2: PERF neural_update [systolic 4x4 banked=1 wbuf=2] cycles_min=28937 cycles_max=28937
fly_core_serial: PERF neural_update [serial] cycles_min=65800 cycles_max=65800
fly_core_2x2_banked_wbuf2: PERF neural_update [systolic 2x2 banked=1 wbuf=2] cycles_min=65799 cycles_max=65799
fly_core_4x4_simple_wbuf1: PERF neural_update [systolic 4x4 banked=0 wbuf=1] cycles_min=106757 cycles_max=106757
fly_core_8x8_banked_wbuf2: PERF neural_update [systolic 8x8 banked=1 wbuf=2] cycles_min=13581 cycles_max=13581
```
