# Local WSL validation — 2026-09-30

Executed on the user's computer in WSL distribution `Ubuntu` (Ubuntu 26.04.1 LTS), not Claude's cloud environment.

## Environment

- Vivado/XSim: 2025.2, installed at `/opt/AMD/2025.2/Vivado`.
- Shell setup: `source /opt/AMD/2025.2/Vivado/settings64.sh`.
- Inventory: `reports/env/linux_Ubuntu.txt`, refreshed after dependency installation.
- Installed `build-essential` in this WSL distribution because XSim elaboration failed with `/usr/bin/gcc not found`. This installed GCC/G++, make, and package dependencies; apt also upgraded five dependencies. Vivado was already installed.
- No FPGA USB device or `/dev/ttyUSB*` was visible in this distribution during inventory. No board programming was performed.

## Simulator capability check

Ran `bash scripts/vivado/xsim_run.sh check` successfully after fixing its probe invocation:

- Added explicit `--timescale 1ns/1ps` to resolve the bundled UVM timescale elaboration error.
- Added explicit error exits for compilation, elaboration, simulation, and missing expected output markers. The original script could exit successfully after a failed elaboration.
- Enabled statement/branch/condition/toggle code coverage for the probe.
- SVA: the intentionally failing assertion emitted exactly one `Error: sva fired (expected once)`.
- Functional coverage: the probe covergroup reported `100.0`.
- UVM: the bundled library compiled and produced `UVM library compiled and ran`.
- Code coverage: simulation generated its coverage database. XCRG successfully generated HTML reports for code and functional coverage.

Logs: `build/xsim/probe/{xvlog,xelab,xsim,xcrg}.log`.

Coverage reports: `build/xsim/probe/coverage_report/`.

Report command, from the probe directory with the Vivado environment loaded:

```bash
xcrg -cov_db_dir . -cov_db_name probe -report_dir coverage_report -report_format html
```

These results establish basic local tool capability only. They do not establish coverage closure or functional correctness of the complete FPGA design. The project directed/UVM regression suites were not run in this task.

## Requested full-board build

Ran:

```bash
bash scripts/vivado/run_vivado.sh build sys4x4_banked_wbuf2 top
```

Synthesis, placement, routing, and bitstream generation completed. The process exited with status 0, but timing did NOT meet the 100 MHz target.

| Post-route measurement | Result |
|---|---:|
| FPGA | xc7a35tcpg236-1 |
| Clock constraint | 10 ns / 100 MHz |
| Worst setup slack | -3.428 ns (FAIL) |
| Worst hold slack | +0.038 ns |
| Slice LUTs | 3514 |
| Slice registers | 4359 |
| DSPs | 0 |
| Block RAM tiles | 3 |
| LUTs used as memory | 189 |

Bitstream: `build/vivado/top_sys4x4_banked_wbuf2/basys3_top.bit`.

Routed checkpoint: `build/vivado/top_sys4x4_banked_wbuf2/routed.dcp`.

Build transcript: `reports/impl/top_sys4x4_banked_wbuf2_build.log`.

Collected results: `reports/impl/results.md` and `reports/impl/results.csv`.

The worst reported setup path goes from the MVU output-index register to a neuron-potential state register, traversing state selection and LIF arithmetic (17 logic levels; data-path delay 13.329 ns). Pipelining this read/update/write path is a candidate for a subsequent RTL fix and functional re-verification; no such RTL change was made in this task.

The timing report found no unconstrained internal endpoints, but the existing XDC intentionally false-paths asynchronous inputs and LED/UART outputs. Methodology warnings include suboptimal RAM output timing, small multipliers, and large setup violations.

The generated bitstream is NOT timing-closed at 100 MHz. Do not present it as validated hardware operation. No RTL or timing constraints were changed, and no commit was made.
