# FPGA fly project: setup and run steps

Status as of 2026-10-01. The project is built and tested:

- 256-neuron FlyWire subcircuit, 4x4 systolic engine
- Vivado/XSim tests pass
- Bitstream meets timing at 100 MHz
- Ran live on the Basys 3, with the dashboard over USB

## Where things are

| What | Where |
|---|---|
| Project folder (Windows) | `C:\Users\duyda\Desktop\personal_projects\fly_fpga` |
| Same folder in Ubuntu (WSL) | `~/fly_fpga`, a link to `/mnt/c/Users/duyda/Desktop/personal_projects/fly_fpga` |
| Vivado | `/opt/AMD/2025.2/Vivado`, inside the Ubuntu WSL distro |
| Bitstream | `build/vivado/top_sys4x4_banked_wbuf2/basys3_top.bit` |
| Board | Basys 3. USB device `0403:6010`, usually bus `3-1` in `usbipd list` |

Run each command on its own line and wait for it to finish before the next.

## A. Run the demo (board already built)

1. **Windows PowerShell:** attach the board to WSL and leave this window open.
   ```powershell
   usbipd list
   usbipd attach --wsl --busid 3-1 --auto-attach
   ```
   Use the bus ID that `usbipd list` shows for 0403:6010.

2. **Ubuntu:**
   ```bash
   cd ~/fly_fpga
   bash scripts/demo.sh
   ```
   This checks the USB connection, programs the FPGA, closes any old dashboard, and opens the live dashboard.
   - If the board is already programmed, use `bash scripts/demo.sh --no-program`.
   - LED 5 on means the weights have loaded. The dashboard banner should be green and read **LIVE FPGA**.

3. **Board controls:**

   | Control | Function |
   |---|---|
   | sw0 | run (off = pause) |
   | btnU | single step while paused |
   | sw1 + btnL | place food in front of the fly. The sugar neurons, then the proboscis neurons fire, and the fly eats. |
   | sw2 + btnR | place a threat beside the fly. The looming neurons, then the giant fiber fire, and the fly jumps away. |
   | sw3 | slow mode (10 steps/s) |
   | sw9..sw5 | which 8 neurons' voltages the dashboard shows |
   | btnC | reset |

Powering off the board erases the design, so program it again next time (step 2 does this).

## B. Rebuild and re-verify (only after design changes)

```bash
cd ~/fly_fpga
source /opt/AMD/2025.2/Vivado/settings64.sh
bash scripts/vivado/xsim_run.sh directed 2>&1 | tee build/xsim_directed.log
bash scripts/vivado/run_vivado.sh build sys4x4_banked_wbuf2 top 2>&1 | tee build/vivado_top.log
```

- **Simulation:** expect 6 PASS lines (lif, uart, world, mvu_4x4, mvu_serial, fly_core). fly_core takes several minutes.
- **Build:** about 10-20 minutes. Check `build/vivado/top_sys4x4_banked_wbuf2/summary.txt`: `wns_ns` and `whs_ns` must be 0 or higher.
- **Optional extras:**
  - UVM random test: `bash scripts/vivado/xsim_run.sh uvm mvu_random_test 1`
  - Full comparison builds: `bash scripts/vivado/run_vivado.sh compare` (long)

## C. Fresh machine (one-time setup)

1. WSL Ubuntu with Vivado 2025.2 installed at `/opt/AMD/2025.2/Vivado`, including Artix-7 support. If the installer complains, it needs the `en_US.UTF-8` locale, `libtinfo5` and `libncurses5`.
2. Vivado cable drivers, run inside Ubuntu:
   ```bash
   sudo /opt/AMD/2025.2/Vivado/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers
   ```
3. usbipd-win on Windows, then share the board once (admin PowerShell):
   ```powershell
   winget install --interactive --exact dorssel.usbipd-win
   usbipd bind --busid 3-1
   ```
4. Ubuntu packages, serial-port permission, and the dashboard's Python environment:
   ```bash
   sudo apt install -y python3-tk python3-venv
   sudo usermod -aG dialout $USER
   ```
   Run `wsl --shutdown` in PowerShell and reopen Ubuntu, then:
   ```bash
   cd ~/fly_fpga
   bash scripts/setup_python.sh
   ```
   It should end with `PASS dashboard selftest`.
5. Project link in your Ubuntu home folder:
   ```bash
   ln -s /mnt/c/Users/duyda/Desktop/personal_projects/fly_fpga ~/fly_fpga
   ```
6. Optional, only to re-pick FlyWire neurons:
   - download the FAFB v783 files into `data/flywire/` (see `docs/flywire.md`)
   - install the extra packages: `.venv/bin/pip install -r requirements-flywire.txt`

## Troubleshooting

| Symptom | Fix |
|---|---|
| Dashboard shows LINK LOST / `/dev/ttyUSB1` missing | WSL lost the USB device. Re-run `usbipd attach --wsl --busid 3-1 --auto-attach`. The dashboard reconnects by itself. |
| "already in use - is another dashboard open?" | `pkill -f fly_dashboard`, then start one again |
| LED 5 off | Board reset or power-cycled: program it again |
| Dashboard or Vivado window invisible, "COPY MODE" | `wsl --shutdown` in PowerShell, reopen Ubuntu, attach the board again |
| `[200~` appears in a command | Paste glitch: Ctrl+C, then paste or type the line again |
| Fly stuck in a corner with the threat on | Known world-rule limitation. Press btnR or turn sw2 off. |
| Lots of USB drops | Disable Windows "USB selective suspend" in Power Options |

Key documents in the repo:

- `docs/specification.md`
- `docs/flywire.md`
- `docs/verification_plan.md`
- `reports/regression/summary.md`
- `reports/impl/results.md`
