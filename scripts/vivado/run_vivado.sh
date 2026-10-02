#!/usr/bin/env bash
# run_vivado.sh - Vivado builds and comparisons from Linux/WSL.
#
#   scripts/vivado/run_vivado.sh find
#   scripts/vivado/run_vivado.sh build <config> [top|mvu]
#   scripts/vivado/run_vivado.sh compare
#   scripts/vivado/run_vivado.sh program [bitfile]
#
# Vivado is found from $VIVADO_SETTINGS (path to settings64.sh), PATH, or the
# usual install roots. Programming from WSL needs the board's USB device passed
# through (usbipd-win: `usbipd attach --wsl --busid <id>`) and Digilent cable
# drivers inside Linux; programming from Windows Vivado or Hardware Manager is
# usually simpler.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if ! command -v vivado >/dev/null; then
    s="${VIVADO_SETTINGS:-}"
    if [ -z "$s" ]; then
        s=$(ls -d /tools/Xilinx/Vivado/*/settings64.sh /tools/Xilinx/*/Vivado/settings64.sh \
                 /opt/Xilinx/Vivado/*/settings64.sh /opt/Xilinx/*/Vivado/settings64.sh \
                 /tools/AMD/*/Vivado/settings64.sh /opt/AMD/*/Vivado/settings64.sh \
                 "$HOME"/Xilinx/Vivado/*/settings64.sh 2>/dev/null | sort -r | head -1 || true)
    fi
    [ -n "$s" ] || { echo "Vivado not found; set VIVADO_SETTINGS=/path/to/settings64.sh"; exit 1; }
    # shellcheck disable=SC1090
    source "$s"
fi
V="vivado -mode batch -nojournal -nolog -notrace"

case "${1:-find}" in
find)    command -v vivado; vivado -version | head -2 ;;
build)   $V -source scripts/vivado/build.tcl -tclargs "$2" "${3:-top}"; python3 scripts/collect_impl.py ;;
compare)
    for c in serial sys2x2_simple sys2x2_banked sys4x4_simple sys4x4_banked sys4x4_banked_wbuf2 \
             sys4x4_banked_wbuf3 sys8x8_banked_wbuf2; do
        $V -source scripts/vivado/build.tcl -tclargs "$c" mvu || echo "build $c failed"
    done
    for c in serial sys4x4_banked_wbuf2; do
        $V -source scripts/vivado/build.tcl -tclargs "$c" top || echo "top $c failed"
    done
    python3 scripts/collect_impl.py ;;
program) $V -source scripts/vivado/program.tcl -tclargs "${2:-build/vivado/top_sys4x4_banked_wbuf2/basys3_top.bit}" ;;
*) echo "usage: $0 find | build <config> [top|mvu] | compare | program [bit]"; exit 2 ;;
esac
