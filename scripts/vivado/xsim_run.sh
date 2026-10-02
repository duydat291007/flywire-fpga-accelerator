#!/usr/bin/env bash
# xsim_run.sh - run testbenches in Vivado's simulator (XSim).
# Source Vivado's settings64.sh first (or have xvlog/xelab/xsim on PATH).
#
#   scripts/vivado/xsim_run.sh check            # probe SV/SVA/UVM/coverage support
#   scripts/vivado/xsim_run.sh directed         # tb_mvu + tb_fly_core + tb_lif, with SVA
#   scripts/vivado/xsim_run.sh all              # directed + UVM random test, logs in build/
#   scripts/vivado/xsim_run.sh uvm [test] [seed] [extra generics]
#        e.g. uvm mvu_random_test 7     uvm mvu_stress_test 3 "USE_SERIAL=1"
#
# Logs: build/xsim/<name>/*.log. Coverage database: build/xsim/uvm_*/xsim.covdb
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
MVU="rtl/core/systolic_pe.sv rtl/core/systolic_array.sv rtl/core/weight_memory.sv rtl/core/mvu_systolic.sv rtl/core/mvu_serial.sv"
NEURAL="rtl/common/fly_cfg_pkg.sv rtl/neural/lif_update.sv rtl/neural/lif_pipe.sv rtl/neural/fly_world.sv rtl/neural/fly_core.sv"
SVA="tb/sva/mvu_sva.sv tb/sva/mvu_binds.sv tb/sva/fly_sva.sv"

for t in xvlog xelab xsim; do
    command -v $t >/dev/null || { echo "ERROR: $t not on PATH (source settings64.sh)"; exit 1; }
done

run() {   # name top "files" [xelab extra]
    local name=$1 top=$2 files=$3 extra=${4:-}
    local d="build/xsim/$name"; rm -rf "$d"; mkdir -p "$d"
    # Testbenches open tests/vectors/* and rtl/common/*.mem relative to the
    # run directory: link them in (copy if the filesystem refuses links).
    ( cd "$d"
      for l in tests rtl; do ln -sfn "$ROOT/$l" "$l" 2>/dev/null || cp -r "$ROOT/$l" "$l"; done
      # Absolute paths in an array: the project path may contain spaces
      local srcs=(); for f in $files; do srcs+=("$ROOT/$f"); done
      xvlog -sv "${srcs[@]}" > xvlog.log 2>&1 || { echo "FAIL $name (xvlog)"; tail -20 xvlog.log; return 1; }
      xelab -debug typical $extra "$top" -s sim > xelab.log 2>&1 || { echo "FAIL $name (xelab)"; tail -20 xelab.log; return 1; }
      xsim sim -R > xsim.log 2>&1
      if grep -qE "^PASS|^DONE" xsim.log && ! grep -qE "FAIL|Error:|Fatal" xsim.log; then
          echo "PASS $name: $(grep -E '^PASS|^DONE' xsim.log | head -1)"
      else
          echo "FAIL $name"; grep -E "FAIL|Error|Fatal" xsim.log | head -10; return 1
      fi )
}

case "${1:-directed}" in
check)
    echo "== xsim version"; xsim -version | head -2
    d=build/xsim/probe; rm -rf $d; mkdir -p $d; cd $d
    cat > probe.sv <<'EOF'
`timescale 1ns/1ps
module probe;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  logic clk = 0, a = 0, b = 0; always #5 clk = ~clk;
  a_p: assert property (@(posedge clk) a |=> b) else $error("sva fired (expected once)");
  covergroup cg @(posedge clk); coverpoint a; endgroup
  cg c = new;
  initial begin
    #12 a = 1; #10 a = 0;
    #50 $display("PROBE coverage=%0.1f", c.get_coverage());
    `uvm_info("PROBE", "UVM library compiled and ran", UVM_NONE)
    $finish;
  end
endmodule
EOF
    xvlog -sv -L uvm probe.sv > xvlog.log 2>&1 || { cat xvlog.log; exit 1; }
    xelab probe -L uvm --timescale 1ns/1ps --cc_type sbct --cov_db_name probe -s probe > xelab.log 2>&1 || { cat xelab.log; exit 1; }
    xsim probe -R > xsim.log 2>&1 || { cat xsim.log; exit 1; }
    echo "== results (see build/xsim/probe/*.log)"
    grep -E "PROBE|sva fired|ERROR|Error" xvlog.log xelab.log xsim.log | head -20
    echo "Expected: one 'sva fired' error (SVA works), PROBE coverage line, UVM_INFO PROBE line."
    grep -q 'sva fired (expected once)' xsim.log &&
    grep -q 'PROBE coverage=' xsim.log &&
    grep -q 'UVM library compiled and ran' xsim.log || exit 1 ;;
directed)
    fail=0
    run lif         tb_lif         "rtl/neural/lif_update.sv rtl/neural/lif_pipe.sv tb/unit/tb_lif.sv" || fail=1
    run uart        tb_uart_tx     "rtl/uart/uart_tx.sv tb/unit/tb_uart_tx.sv" || fail=1
    run world       tb_fly_world   "rtl/common/fly_cfg_pkg.sv rtl/neural/fly_world.sv tb/unit/tb_fly_world.sv" || fail=1
    run mvu_4x4     tb_mvu         "$MVU tb/sva/mvu_sva.sv tb/sva/mvu_binds.sv tb/integration/tb_mvu.sv" || fail=1
    run mvu_serial  tb_mvu         "$MVU tb/sva/mvu_sva.sv tb/sva/mvu_binds.sv tb/integration/tb_mvu.sv" "-generic_top USE_SERIAL=1" || fail=1
    run fly_core    tb_fly_core    "$MVU $NEURAL $SVA tb/integration/tb_fly_core.sv" || fail=1
    exit $fail ;;
uvm)
    test=${2:-mvu_random_test}; seed=${3:-1}; gen=${4:-}
    name="uvm_${test}_s${seed}${gen:+_$(echo $gen | tr '= ' '__')}"
    d="build/xsim/$name"; rm -rf "$d"; mkdir -p "$d"; cd "$d"
    srcs=(); for f in $MVU tb/sva/mvu_sva.sv tb/sva/mvu_binds.sv tb/uvm/mvu_if.sv tb/uvm/mvu_uvm_pkg.sv tb/uvm/tb_uvm_top.sv; do srcs+=("$ROOT/$f"); done
    xvlog -sv -L uvm "${srcs[@]}" > xvlog.log 2>&1 || { echo "FAIL xvlog"; tail -30 xvlog.log; exit 1; }
    # --timescale: XSim's bundled uvm_pkg has none, while the design files do
    xelab -L uvm --timescale 1ns/1ps -debug typical -cc_type sbct -cov_db_dir . -cov_db_name fcov tb_uvm_top -s sim \
          $(for g in $gen; do echo "-generic_top $g"; done) > xelab.log 2>&1 || { echo "FAIL xelab"; tail -30 xelab.log; exit 1; }
    xsim sim -R -sv_seed "$seed" -testplusarg "UVM_TESTNAME=$test" -cov_db_dir . -cov_db_name fcov > xsim.log 2>&1
    grep -E "PASS|FAIL|UVM_ERROR :|UVM_FATAL :|\[SB\]|\[COV\]" xsim.log | tail -8
    echo "Coverage report: xcrg -dir . -db_name fcov -report_dir cov_report -report_format html" ;;
all)
    # Directed tests, then the UVM random test; each saves its own log in build/
    bash "$0" directed 2>&1 | tee build/xsim_directed.log
    bash "$0" uvm mvu_random_test 1 2>&1 | tee build/xsim_uvm.log
    echo; echo "Logs: build/xsim_directed.log build/xsim_uvm.log" ;;
*)  echo "usage: $0 check | directed | uvm [test] [seed] [generics] | all"; exit 2 ;;
esac
