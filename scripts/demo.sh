#!/usr/bin/env bash
# demo.sh - one command for the live board demo from WSL.
#   1. checks the Basys 3 is attached to WSL (usbipd)
#   2. programs the FPGA unless --no-program
#   3. closes any old dashboard, then starts one on the telemetry port
# Usage: bash scripts/demo.sh [--no-program] [--port /dev/ttyUSBn]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PROGRAM=1; PORT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-program) PROGRAM=0 ;;
        --port) PORT="$2"; shift ;;
        *) echo "unknown option $1"; exit 2 ;;
    esac
    shift
done

if ! lsusb 2>/dev/null | grep -qi "0403:6010"; then
    echo "Basys 3 not visible in WSL. In Windows PowerShell run:"
    echo "    usbipd attach --wsl --busid <BUSID> --auto-attach"
    echo "(find BUSID with 'usbipd list': the 0403:6010 device), then rerun this script."
    exit 1
fi

if [ "$PROGRAM" = 1 ]; then
    [ -f build/vivado/top_sys4x4_banked_wbuf2/basys3_top.bit ] || { echo "no bitstream: build it first"; exit 1; }
    command -v vivado >/dev/null || source /opt/AMD/2025.2/Vivado/settings64.sh
    bash scripts/vivado/run_vivado.sh program 2>&1 | grep -E "Programmed|ERROR" || { echo "programming failed"; exit 1; }
    sleep 2       # weights load in < 1 ms; give the USB-UART time to settle after JTAG
fi

pkill -f fly_dashboard 2>/dev/null && sleep 1
if [ -z "$PORT" ]; then
    # telemetry is the highest-numbered ttyUSB that belongs to the Digilent board
    PORT=$(ls /dev/ttyUSB* 2>/dev/null | sort -V | tail -1)
fi
[ -n "$PORT" ] || { echo "no /dev/ttyUSB* port found"; exit 1; }
[ -x .venv/bin/python ] || { echo "run: bash scripts/setup_python.sh"; exit 1; }
echo "Starting dashboard on $PORT (LED5 on the board = weights loaded)"
exec .venv/bin/python dashboard/fly_dashboard.py --port "$PORT"
