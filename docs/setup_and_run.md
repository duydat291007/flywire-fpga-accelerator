# FPGA fly project: setup and run steps

## Status (2026-10-02, evening)

The project is complete and published at https://github.com/duydat291007/flywire-fpga-accelerator. The latest commit is "Update regression summary (63/63)".

- **Board:** the FlyWire design is stored in the board's flash, and jumper JP1 is on **QSPI**. The board starts the design by itself whenever it powers on: LED 5 lights within about a second. No laptop programming is needed.
- **Timing at 100 MHz:** both builds pass. The 4×4 systolic build has +0.904 ns setup slack (289 µs per update); the serial build has +0.984 ns (658 µs).
- **Checks:** 63/63 cloud checks pass, and all 6 tests pass in Vivado's simulator.
- **Behavior:** a cornered fly now escapes along a wall.

To publish future changes:

```bash
cd ~/fly_fpga
git add -A
git commit -m "message"
git push
```

The remaining optional step is a short demo video linked from the README.

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

## A. Run the demo

The board boots the FlyWire design from flash on its own (JP1 = QSPI). You only need the laptop to watch the dashboard.

1. **Power the board** with the USB cable. LED 5 should turn on.
2. **Open Ubuntu first** and leave it open. usbipd can only attach the board while WSL is running.
3. **Windows PowerShell:** attach the board to WSL and leave this window open.
   ```powershell
   usbipd attach --wsl --busid 3-1 --auto-attach
   ```
   If the bus ID has changed, run `usbipd list` and use the one shown for 0403:6010.
4. **Ubuntu:** open the dashboard without reprogramming.
   ```bash
   cd ~/fly_fpga
   bash scripts/demo.sh --no-program
   ```
   The dashboard banner should be green and read **LIVE FPGA**.

After rebuilding the design, `bash scripts/demo.sh` (without `--no-program`) loads the new bitstream over USB until the next power-off. Run `bash scripts/vivado/run_vivado.sh flash` (section C) to make it the design the board boots.

5. **Board controls:**

   | Control | Function |
   |---|---|
   | sw0 | run (off = pause) |
   | btnU | single step while paused |
   | sw1 + btnL | place food in front of the fly; it eats |
   | sw2 + btnR | place a threat beside the fly; it jumps away |
   | sw3 | slow mode (10 steps/s) |
   | sw9..sw5 | which 8 neurons' voltages the dashboard shows |
   | btnC | reset |

Programming over USB (demo.sh) lasts until power-off. To make the design load by itself at power-on, see section C.

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

## C. Boot from flash (survives power-off)

1. Build as usual. The build also writes `build/vivado/top_sys4x4_banked_wbuf2/basys3_top.bin`.
2. With the board attached to WSL:
   ```bash
   bash scripts/vivado/run_vivado.sh flash
   ```
   This takes 1–3 minutes and should end with `Flash programmed and verified`.
3. Unplug the board, move the mode jumper **JP1** to the top pair of pins, labelled **QSPI**, and plug it back in. The design starts by itself, and LED 5 lights within about a second.

To go back, put JP1 on JTAG or USB; programming from the laptop works in any position.

## D. Fresh machine (one-time setup)

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
| usbipd: "There is no WSL 2 distribution running" | Open Ubuntu first, then run the attach command again |
| Dashboard shows LINK LOST / `/dev/ttyUSB1` missing | Re-run `usbipd attach --wsl --busid 3-1 --auto-attach`. The dashboard reconnects by itself. |
| "already in use - is another dashboard open?" | `pkill -f fly_dashboard`, then start one again |
| LED 5 off at power-on | Check JP1 is on QSPI (top pins). Otherwise program it with `bash scripts/demo.sh` |
| Window invisible or "COPY MODE" | `wsl --shutdown` in PowerShell, reopen Ubuntu, attach the board again |
| `[200~` appears in a command | Paste glitch: Ctrl+C, then paste or type the line again |
| Fly pinned near a wall with the threat on | Less common since the ±135° escape rule. Press btnR or turn sw2 off. |
| git says `index.lock` exists | `rm -f ~/fly_fpga/.git/index.lock` |
