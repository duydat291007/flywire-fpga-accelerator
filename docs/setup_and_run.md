# FPGA fly project: setup and run steps

## Where we left off (2026-10-02, 4:30 AM)

**Done:**

- 256-neuron FlyWire design ran live on the board.
- Pushed to GitHub: https://github.com/duydat291007/flywire-fpga-accelerator
- Fixed three timing problems found while rebuilding the serial baseline (in `fly_world.sv` and `mvu_serial.sv`).
- All cloud tests pass after the fixes, and the files are in the project folder.

**Next steps:**

1. In Ubuntu, one line at a time (about 40 minutes):
   ```bash
   cd ~/fly_fpga
   source /opt/AMD/2025.2/Vivado/settings64.sh
   bash scripts/vivado/xsim_run.sh directed 2>&1 | tee build/xsim_directed_v4.log
   bash scripts/vivado/run_vivado.sh build serial top 2>&1 | tee build/vivado_serial_v6.log
   bash scripts/vivado/run_vivado.sh build sys4x4_banked_wbuf2 top 2>&1 | tee build/vivado_top_v4.log
   ```
2. Tell Claude "done". Claude checks that both builds meet timing and updates the README numbers.
3. Commit and push:
   ```bash
   git add -A
   git commit -m "Timing fixes and current serial/systolic results"
   git push
   ```
4. Program the new bitstream: plug in the board, attach it with usbipd (section A), then run `bash scripts/demo.sh`.

Last known results:

| Build | Setup slack | Notes |
|---|---|---|
| Systolic 4×4 | +0.435 ns | before the latest world fix |
| Serial | -0.221 ns | the latest fix targets this path |

## Where things are

| What | Where |
|---|---|
| Project folder (Windows) | `C:\Users\duyda\Desktop\personal_projects\fly_fpga` (the real files live here) |
| Same folder in Ubuntu | `~/fly_fpga`, a link to `/mnt/c/Users/duyda/Desktop/personal_projects/fly_fpga`. Always start with `cd ~/fly_fpga`. |
| In Vivado's file browser | Your home folder → `fly_fpga` |
| GitHub | https://github.com/duydat291007/flywire-fpga-accelerator (local folder linked as `origin`) |
| Vivado | `/opt/AMD/2025.2/Vivado`, inside the Ubuntu WSL distro |
| Bitstream | `build/vivado/top_sys4x4_banked_wbuf2/basys3_top.bit` |
| Board | Basys 3. USB device `0403:6010`, usually bus `3-1` in `usbipd list` |

Run each command on its own line and wait for it to finish before the next.

## A. Run the demo (board already built)

1. **Windows PowerShell:** attach the board to WSL and leave this window open.
   ```powershell
   usbipd attach --wsl --busid 3-1 --auto-attach
   ```
   If the bus ID has changed, run `usbipd list` and use the one shown for 0403:6010.
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
   | sw1 + btnL | place food in front of the fly; it eats |
   | sw2 + btnR | place a threat beside the fly; it jumps away |
   | sw3 | slow mode (10 steps/s) |
   | sw9..sw5 | which 8 neurons' voltages the dashboard shows |
   | btnC | reset |

Powering off the board erases the design, so program it again next time.

## B. Rebuild and re-verify (after design changes)

```bash
cd ~/fly_fpga
source /opt/AMD/2025.2/Vivado/settings64.sh
bash scripts/vivado/xsim_run.sh directed 2>&1 | tee build/xsim_directed.log
bash scripts/vivado/run_vivado.sh build sys4x4_banked_wbuf2 top 2>&1 | tee build/vivado_top.log
```

- **Simulation:** expect 6 PASS lines.
- **Build:** check `build/vivado/top_sys4x4_banked_wbuf2/summary.txt`. `wns_ns` and `whs_ns` must be 0 or higher.
- **Serial baseline:** `bash scripts/vivado/run_vivado.sh build serial top`
- **Vivado GUI project:** `vivado -mode batch -source scripts/vivado/create_project.tcl`, then open `build/vivado_gui/fly_fpga.xpr`.

## C. Fresh machine (one-time setup)

1. WSL Ubuntu with Vivado 2025.2 at `/opt/AMD/2025.2/Vivado`, including Artix-7 support. The installer needs the `en_US.UTF-8` locale, `libtinfo5` and `libncurses5`.
2. Cable drivers, run inside Ubuntu:
   ```bash
   sudo /opt/AMD/2025.2/Vivado/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers
   ```
3. usbipd-win on Windows, then share the board once (admin PowerShell):
   ```powershell
   winget install --interactive --exact dorssel.usbipd-win
   usbipd bind --busid 3-1
   ```
4. Get the project: clone it from GitHub, or use the Windows folder above, and link it:
   ```bash
   ln -s /mnt/c/Users/duyda/Desktop/personal_projects/fly_fpga ~/fly_fpga
   ```
5. Ubuntu packages and serial-port permission:
   ```bash
   sudo apt install -y python3-tk python3-venv gh
   sudo usermod -aG dialout $USER
   ```
   Then run `wsl --shutdown` in PowerShell, reopen Ubuntu, and set up Python:
   ```bash
   cd ~/fly_fpga
   bash scripts/setup_python.sh
   ```
   It should end with `PASS dashboard selftest`.
6. GitHub login for pushing: `gh auth login` (GitHub.com, HTTPS, log in with a web browser).

## Troubleshooting

| Symptom | Fix |
|---|---|
| Dashboard shows LINK LOST / `/dev/ttyUSB1` missing | Re-run `usbipd attach --wsl --busid 3-1 --auto-attach`. The dashboard reconnects by itself. |
| "already in use - is another dashboard open?" | `pkill -f fly_dashboard`, then start one again |
| LED 5 off | Board reset or power-cycled: program it again |
| Window invisible or "COPY MODE" | `wsl --shutdown` in PowerShell, reopen Ubuntu, attach the board again |
| `[200~` appears in a command | Paste glitch: Ctrl+C, then paste or type the line again |
| Fly stuck in a corner with the threat on | Known world-rule limitation. Press btnR or turn sw2 off. |
| git says `index.lock` exists | `rm -f ~/fly_fpga/.git/index.lock` |
