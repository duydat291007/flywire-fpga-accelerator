# Environments

Every build, simulation, and measurement in this project names the environment it
ran in. Results from one environment are never reported as coming from another.

| ID | What it is | How identified | Who can run things there |
|---|---|---|---|
| **CLOUD** | Claude's cloud sandbox (Linux container in Anthropic's cloud). Not your machine. | Icarus Verilog 12.0 and Verilator 5.020 installed here with `apt` for this project. No Vivado. | Claude only |
| **DESKTOP-VM** | The Claude desktop app's own sandbox VM on your laptop: Ubuntu 22.04.5, kernel `6.8.0-138-generic`, Hyper-V (`systemd-detect-virt` = `microsoft`), hostname `claude`, 2 CPUs / 3 GB. Sees only the connected project folder. **Not** your WSL. | Inspected 2026-09-30 | Claude only (file bridge) |
| **WIN** | Your Windows laptop (`bland3`), PowerShell | Folder listing only so far; Vivado not found in `C:\Xilinx`, `C:\AMDDesign`, `C:\Program Files`, `%LOCALAPPDATA%\Programs` | You |
| **WSL** | Your WSL2 installation: two distro instances under `%LOCALAPPDATA%\wsl\{GUID}` | Names/versions pending `scripts\inspect_env.ps1` | You |

The file bridge cannot open `\\wsl.localhost\` paths, and computer control may click
but not type in terminals, so Claude cannot run commands in **WIN** or **WSL**.
`scripts/inspect_env.ps1` (read-only) inventories WIN and then runs
`scripts/inspect_env.sh` inside every WSL distro; reports land in `reports/env/`.

## Run log

| Date | Env | Tool | What | Result |
|---|---|---|---|---|
| 2026-09-30 | CLOUD | Python 3 | reference-model smoke test (CRC check value, food/threat behavior) | CRC `0x29B1` correct; behavior as designed |
| 2026-09-30 | CLOUD | Icarus 12.0 | `tb_mvu`, `mvu_serial`, 86 vector cases (seed 20260930 / tb seed 1) | PASS |
| 2026-09-30 | CLOUD | Icarus 12.0 | `tb_mvu`, `mvu_systolic` configurations | not yet run |
