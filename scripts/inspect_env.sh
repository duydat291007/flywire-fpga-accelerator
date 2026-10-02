#!/usr/bin/env bash
# inspect_env.sh - read-only inventory of one Linux environment (WSL distro,
# VM, or native). Installs nothing. Writes reports/env/linux_<name>.txt.
# Normally launched for every WSL distro by scripts/inspect_env.ps1.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
name="${WSL_DISTRO_NAME:-$(hostname)}"
out="$here/reports/env/linux_${name// /_}.txt"
mkdir -p "$here/reports/env"
exec > "$out" 2>&1

section() { printf '\n== %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

section "timestamp"; date -Is
section "identity"
echo "WSL_DISTRO_NAME=${WSL_DISTRO_NAME:-<unset>}"; uname -a; cat /proc/version
grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release 2>/dev/null
section "environment type"
if grep -qi 'microsoft-standard-wsl2' /proc/version; then echo "WSL2"
elif grep -qi microsoft /proc/version; then echo "WSL1"
elif have systemd-detect-virt; then echo "virt: $(systemd-detect-virt 2>/dev/null)"
else echo "unknown"; fi
[ -e /mnt/c/Windows ] && echo "Windows C: mounted at /mnt/c"
cat /etc/wsl.conf 2>/dev/null
section "resources"; nproc; free -h | head -2; df -h / "$here" 2>/dev/null
section "project path as seen here"; echo "$here"

section "Vivado search"
have vivado && { echo "on PATH: $(command -v vivado)"; }
for s in $( { ls -d /tools/Xilinx/*/Vivado/*/settings64.sh /tools/Xilinx/Vivado/*/settings64.sh \
              /opt/Xilinx/*/Vivado/*/settings64.sh /opt/Xilinx/Vivado/*/settings64.sh \
              /tools/AMD/*/Vivado/settings64.sh /opt/AMD/*/Vivado/settings64.sh \
              /tools/Xilinx/*/Vivado/settings64.sh /opt/Xilinx/*/Vivado/settings64.sh \
              "$HOME"/Xilinx/*/Vivado/*/settings64.sh "$HOME"/Xilinx/Vivado/*/settings64.sh \
              "$HOME"/AMD/*/Vivado/settings64.sh 2>/dev/null; \
            find / -xdev -maxdepth 6 -name settings64.sh -path '*Vivado*' 2>/dev/null; } | sort -u ); do
  d="$(dirname "$s")"
  echo "--- install: $d"
  ( source "$s" >/dev/null 2>&1
    echo "XILINX_VIVADO=${XILINX_VIVADO:-<unset>}"
    timeout 120 vivado -version 2>&1 | head -3
    timeout 60 xvlog --version 2>&1 | head -2
    ls -d "$XILINX_VIVADO"/data/system_verilog/uvm* 2>/dev/null | sed 's/^/uvm lib: /'
    ls "$XILINX_VIVADO"/data/parts/xilinx 2>/dev/null | grep -i artix | sed 's/^/device family: /'
    ls -d "$XILINX_VIVADO"/data/xicom/cable_drivers 2>/dev/null | sed 's/^/cable drivers dir: /' )
done
section "license environment"
env | grep -iE 'XILINXD_LICENSE_FILE|LM_LICENSE_FILE' || echo "(no license variables set)"
ls "$HOME"/.Xilinx/*.lic 2>/dev/null

section "board / USB visibility"
have lsusb && lsusb | grep -iE '0403|digilent|ftdi' || echo "no lsusb or no FTDI/Digilent device visible"
ls -l /dev/ttyUSB* 2>/dev/null || echo "no /dev/ttyUSB*"

section "other tools"
for t in iverilog vvp verilator yosys python3 pip3 git make gcc; do
  printf '%-10s ' "$t"; if have "$t"; then echo "$(command -v $t)  $($t --version 2>&1 | head -1)"; else echo "not found"; fi
done
if have python3; then
  python3 - <<'PY'
import importlib, sys
print("python", sys.version.split()[0])
for m in ("venv", "tkinter", "numpy", "serial", "pytest"):
    try:
        importlib.import_module(m); print(f"  {m}: yes")
    except Exception as e:
        print(f"  {m}: no ({type(e).__name__})")
PY
fi
echo; echo "report written: $out"
