#!/usr/bin/env python3
"""Regression runner for the Systolic Neural Accelerator project.

Runs (each stage only if its tools are present):
  1. Python model unit tests
  2. deterministic vector/trace generation
  3. Icarus Verilog (4-state) self-checking testbenches
  4. Verilator with SystemVerilog assertions enabled, end-to-end checkers
  5. mutation checks (--mutants): each injected bug must be detected

Writes reports/regression/summary.md and summary.json, recording the host,
tool versions, seeds, per-test results, durations and PERF lines.

Usage (Linux/WSL, from the repository root):
    python3 scripts/run_regression.py              # stages 1-4
    python3 scripts/run_regression.py --mutants    # plus mutation checks
    python3 scripts/run_regression.py --quick      # fewer configurations
"""

import argparse
import datetime
import json
import os
import pathlib
import platform
import re
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "regression"
REPORT = ROOT / "reports" / "regression"

PKG = ["rtl/common/fly_cfg_pkg.sv"]
MVU = ["rtl/core/systolic_pe.sv", "rtl/core/systolic_array.sv", "rtl/core/weight_memory.sv",
       "rtl/core/mvu_systolic.sv", "rtl/core/mvu_serial.sv"]
NEURAL = ["rtl/neural/lif_update.sv", "rtl/neural/lif_pipe.sv", "rtl/neural/fly_world.sv", "rtl/neural/fly_core.sv"]
UART = ["rtl/uart/uart_tx.sv", "rtl/uart/telemetry.sv"]
BOARD = ["rtl/board/input_conditioner.sv", "rtl/board/basys3_top.sv"]
ALL_RTL = PKG + MVU + NEURAL + UART + BOARD
# Measured cycles per neural update for the default 4x4 banked WBUF=2 engine
# (accept .. commit). Telemetry packets must report exactly this value.
NEURAL_CYCLES = 28937

SVA = ["tb/sva/mvu_sva.sv", "tb/sva/mvu_binds.sv", "tb/sva/fly_sva.sv"]
WORLD_TB = PKG + ["rtl/neural/fly_world.sv", "tb/unit/tb_fly_world.sv"]

MVU_CONFIGS = [  # (label, params) for tb_mvu
    ("serial", {"USE_SERIAL": 1}),
    ("4x4_banked_wbuf2", {"ROWS": 4, "COLS": 4, "BANKED": 1, "WBUF": 2}),
    ("4x4_banked_wbuf1", {"ROWS": 4, "COLS": 4, "BANKED": 1, "WBUF": 1}),
    ("4x4_simple_wbuf1", {"ROWS": 4, "COLS": 4, "BANKED": 0, "WBUF": 1}),
    ("4x4_banked_wbuf3", {"ROWS": 4, "COLS": 4, "BANKED": 1, "WBUF": 3}),
    ("2x2_banked_wbuf2", {"ROWS": 2, "COLS": 2, "BANKED": 1, "WBUF": 2}),
    ("2x2_simple_wbuf1", {"ROWS": 2, "COLS": 2, "BANKED": 0, "WBUF": 1}),
    ("2x8_banked_wbuf2", {"ROWS": 2, "COLS": 8, "BANKED": 1, "WBUF": 2}),
    ("8x8_banked_wbuf2", {"ROWS": 8, "COLS": 8, "BANKED": 1, "WBUF": 2}),
    ("1x1_simple_wbuf1", {"ROWS": 1, "COLS": 1, "BANKED": 0, "WBUF": 1}),
]
QUICK_MVU = {"serial", "4x4_banked_wbuf2", "4x4_simple_wbuf1", "2x8_banked_wbuf2"}

# (name, file, original, replacement, test-key, description)
MUTANTS = [
    ("pe_zero_extend", "rtl/core/systolic_pe.sv", "32'(prod)", "32'($unsigned(prod))",
     "mvu_4x4", "product zero-extended instead of sign-extended"),
    ("serial_unsigned", "rtl/core/mvu_serial.sv", "$signed(w_rd) * $signed(x1)",
     "w_rd * x1", "mvu_serial", "serial multiply without signed casts"),
    ("weight_src_mask", "rtl/core/mvu_systolic.sv",
     "assign ld_mask[b] = ((ld_dst0 + b) < dim_q) && (ld_src < dim_q);",
     "assign ld_mask[b] = ((ld_dst0 + b) < dim_q);", "mvu_4x4", "partial-tile source mask removed"),
    ("stale_accumulator", "rtl/core/mvu_systolic.sv", "sum   = first ? ps_col[c]",
     "sum   = 1'b0 ? ps_col[c]", "mvu_4x4", "accumulator not restarted per output group"),
    ("buffer_hazard_wide", "rtl/core/mvu_systolic.sv", "!buf_busy[ld_buf]", "1'b1",
     "mvu_2x8", "weight-buffer hazard check removed (wide array, result checks)"),
    ("buffer_hazard_sva", "rtl/core/mvu_systolic.sv", "!buf_busy[ld_buf]", "1'b1",
     "sva_mvu_4x4", "weight-buffer hazard check removed (square array, assertions)"),
    ("skew_valid", "rtl/core/mvu_systolic.sv", "assign xv_row[r]   = sv[r-1];",
     "assign xv_row[r]   = sv[0];", "mvu_4x4", "input skew of valid bits wrong"),
    ("ignore_backpressure", "rtl/core/mvu_systolic.sv", "S_DRAIN: if (res_ready) begin",
     "S_DRAIN: if (1'b1) begin", "mvu_4x4", "result stream ignores res_ready"),
    ("write_while_busy", "rtl/core/mvu_systolic.sv", "assign w_ready   = !busy;",
     "assign w_ready   = 1'b1;", "mvu_4x4", "weight writes accepted while busy"),
    ("loader_not_reset", "rtl/core/mvu_systolic.sv",
     "            ld_active  <= 1'b0;\n            wl_v       <= 1'b0;",
     "            wl_v       <= 1'b0;", "mvu_4x4", "loader state survives reset"),
    ("lif_strict_gt", "rtl/neural/lif_update.sv", "assign spike  = (cand >= $signed(34'(THRESHOLD)));",
     "assign spike  = (cand > $signed(34'(THRESHOLD)));", "lif", "fires on > instead of >="),
    ("lif_no_clamp", "rtl/neural/lif_update.sv", "(spike || cand[33]) ? 16'd0", "spike ? 16'd0",
     "lif", "negative candidate not clamped to 0"),
    ("lif_pipe_tag_skew", "rtl/neural/lif_pipe.sv", "s2_tag  <= s1_tag;", "s2_tag  <= in_tag;",
     "lif", "pipelined LIF result written to the wrong neuron"),
    ("same_step_contamination", "rtl/neural/fly_core.sv",
     "wire [15:0] v_cur_i = vmem[{cur, res_idx}];",
     "wire [15:0] v_cur_i = vmem[{~cur, res_idx}];",
     "fly_core", "LIF reads the next bank instead of the current bank"),
    ("commit_incomplete", "rtl/neural/fly_core.sv", "S_FLUSH: if (lw_valid && lw_last)  st <= S_COMMIT;",
     "S_FLUSH: if (lw_valid && lw_idx == 8'd254) st <= S_COMMIT;", "sva_fly_core",
     "commit before the last neuron"),
    ("sensor_input_shift", "rtl/neural/fly_core.sv",
     "u_sens_q[res_idx[4:3]] : 8'd0;", "u_sens_q[res_idx[3:2]] : 8'd0;",
     "fly_core", "sensor drive applied to the wrong neurons"),
    ("world_threat_side_flipped", "rtl/neural/fly_world.sv",
     "u_sens[2] <= (s_threat_on && tside <= 0) ? loom : 8'd0;",
     "u_sens[2] <= (s_threat_on && tside >= 0) ? loom : 8'd0;",
     "fly_core", "looming input sent to the wrong side"),
    ("world_steer_reversed", "rtl/neural/fly_world.sv",
     "wire signed [8:0] steer   = $signed({1'b0, acc[M_STR]}) - $signed({1'b0, acc[M_STL]});",
     "wire signed [8:0] steer   = $signed({1'b0, acc[M_STL]}) - $signed({1'b0, acc[M_STR]});",
     "fly_core", "steering neurons turn the fly the wrong way"),
    ("world_threat_period", "rtl/neural/fly_world.sv",
     "if (threat_phase == TPW'(THREAT_PERIOD - 1)) begin",
     "if (threat_phase == TPW'(THREAT_PERIOD - 2)) begin",
     "fly_core", "threat pursues at the wrong rate"),
    ("world_catch_before_pursuit", "rtl/neural/fly_world.sv",
     "                    wst <= W_CATCH;\n                end\n\n                W_CATCH:",
     "                    wst <= W_PEND;\n                end\n\n                W_CATCH:",
     "world", "catch check skipped after a motor window"),
    ("world_corner_escape", "rtl/neural/fly_world.sv",
     "3'd5: return 3'd3;", "3'd5: return 3'd4;",
     "world", "cornered fly jumps back toward the threat instead of along the wall"),
    ("world_jump_toward_threat", "rtl/neural/fly_world.sv",
     "heading <= head_of(-sgn7(tdx), -sgn7(tdy));", "heading <= head_of(sgn7(tdx), sgn7(tdy));",
     "world", "escape jump heads toward the threat"),
    ("world_back_margin", "rtl/neural/fly_world.sv",
     "go_back <= (backdrv >= 9'(BACK_MARGIN));", "go_back <= (backdrv > 9'(BACK_MARGIN));",
     "world", "backing-up threshold off by one"),
    ("world_food_ahead_axis", "rtl/neural/fly_world.sv",
     "food_y <= clamp_add(fly_y, hdy(heading), 4'(FOOD_AHEAD));",
     "food_y <= clamp_add(fly_y, hdx(heading), 4'(FOOD_AHEAD));",
     "world", "food button places food on the wrong axis"),
    ("world_jump_no_retry", "rtl/neural/fly_world.sv",
     "end else if (try_k == 3'd6) begin", "end else if (try_k == 3'd0) begin",
     "fly_core", "jump gives up at a wall instead of trying other headings"),
    ("uart_lsb_msb", "rtl/uart/uart_tx.sv", "shreg     <= {1'b1, in_data, 1'b0};",
     "shreg     <= {1'b1, in_data[0], in_data[1], in_data[2], in_data[3], in_data[4], "
     "in_data[5], in_data[6], in_data[7], 1'b0};", "uart", "data sent MSB first"),
    ("telemetry_no_clear", "rtl/uart/telemetry.sv",
     "act[i] <= (commit && spikes[i]) ? 2'd1 : 2'd0;", "act[i] <= act[i];",
     "telemetry", "activity counters not cleared at capture"),
    ("crc_init", "rtl/uart/telemetry.sv", "            crc      <= 16'hFFFF;\n            seq_sent <= seq_sent + 1'b1;",
     "            crc      <= 16'h0000;\n            seq_sent <= seq_sent + 1'b1;", "telemetry",
     "CRC initial value wrong"),
]


def which(t):
    return shutil.which(t)


def tool_version(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return (out.stdout + out.stderr).strip().splitlines()[0]
    except Exception:
        return "not found"


class Runner:
    def __init__(self, args):
        self.args = args
        self.results = []
        self.perf = []
        BUILD.mkdir(parents=True, exist_ok=True)

    def record(self, name, ok, secs, detail="", sim=""):
        status = "PASS" if ok else "FAIL"
        self.results.append(dict(name=name, sim=sim, status=status, seconds=round(secs, 1),
                                 detail=detail.strip()[:300]))
        print(f"  {status:4}  {name:44} {sim:9} {secs:6.1f}s  {detail.strip()[:70]}", flush=True)

    def sh(self, cmd, cwd=ROOT, timeout=3600):
        t0 = time.time()
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr, time.time() - t0

    # ---------------- simulators ----------------
    def icarus(self, top, files, params=None, root=ROOT, tag=None):
        out = BUILD / f"iv_{tag or top}.vvp"
        cmd = ["iverilog", "-g2012", "-o", str(out), "-s", top]
        for k, v in (params or {}).items():
            cmd.append(f"-P{top}.{k}={v}")
        cmd += [str(root / f) for f in files]
        rc, log, t1 = self.sh(cmd, cwd=root)
        if rc != 0:
            return False, "COMPILE: " + log, t1
        rc, log, t2 = self.sh(["vvp", "-n", str(out)], cwd=root)
        ok = rc == 0 and "PASS" in log and "FAIL" not in log and "FATAL" not in log.upper()
        return ok, log, t1 + t2

    def verilator(self, top, files, params=None, root=ROOT, tag=None, sva=True):
        mdir = BUILD / f"vl_{tag or top}"
        if mdir.exists():
            shutil.rmtree(mdir)
        cmd = ["verilator", "--binary", "--timing", "-j", str(os.cpu_count() or 2), "-Wno-fatal", "-Wno-lint", "-Wno-style",
               "-Mdir", str(mdir), "--top-module", top, "-o", "sim"]
        if sva:
            cmd.append("--assert")
        for k, v in (params or {}).items():
            cmd.append(f"-G{k}={v}")
        cmd += [str(root / f) for f in files]
        rc, log, t1 = self.sh(cmd, cwd=root)
        if rc != 0:
            return False, "COMPILE: " + log[-2000:], t1
        rc, log, t2 = self.sh([str(mdir / "sim")], cwd=root)
        bad = re.search(r"%Error|Assertion failed|FAIL|%Fatal", log)
        ok = rc == 0 and not bad and ("PASS" in log or "DONE" in log)
        return ok, log, t1 + t2

    def first_line(self, log, ok):
        lines = log.splitlines()
        if ok:
            return next((l for l in lines if l.startswith(("PASS", "DONE"))), "")
        return next((l for l in lines if re.search(r"FAIL|Error|Assertion|COMPILE|fatal", l)),
                    lines[-1] if lines else "")

    def grab_perf(self, label, log):
        for l in log.splitlines():
            if l.startswith("PERF"):
                self.perf.append(f"{label}: {l}")

    # ---------------- stages ----------------
    def stage_python(self):
        print("\n== Python model tests")
        rc, log, t = self.sh([sys.executable, "-m", "unittest", "discover", "-s", "model/tests"])
        m = re.search(r"Ran (\d+) tests", log)
        self.record("python_unittest", rc == 0, t, f"{m.group(1) if m else '?'} tests", "python")
        print("\n== Vector generation (deterministic)")
        for script in ("export_rtl.py", "gen_mvu_vectors.py", "gen_fly_trace.py", "gen_fly_trace.py --short",
                       "gen_world_vectors.py", "gen_lif_vectors.py"):
            rc, log, t = self.sh([sys.executable, *f"model/{script}".split()])
            self.record(f"gen_{script.split('.')[0]}{'_short' if '--short' in script else ''}", rc == 0, t, log.strip().splitlines()[-1] if log else "",
                        "python")

    def stage_icarus(self):
        if not which("iverilog"):
            print("\n== Icarus Verilog not found: skipped")
            return
        print(f"\n== Icarus Verilog ({tool_version(['iverilog', '-V'])})")
        for div, nb in ((16, 200), (868, 6)):
            ok, log, t = self.icarus("tb_uart_tx", ["rtl/uart/uart_tx.sv", "tb/unit/tb_uart_tx.sv"],
                                     {"DIV": div, "NBYTES": nb}, tag=f"uart{div}")
            self.record(f"uart_tx_div{div}", ok, t, self.first_line(log, ok), "icarus")
        ok, log, t = self.icarus("tb_lif", ["rtl/neural/lif_update.sv", "rtl/neural/lif_pipe.sv", "tb/unit/tb_lif.sv"])
        self.record("lif_vectors", ok, t, self.first_line(log, ok), "icarus")
        ok, log, t = self.icarus("tb_fly_world", WORLD_TB)
        self.record("world_random", ok, t, self.first_line(log, ok), "icarus")
        for label, params in MVU_CONFIGS:
            if self.args.quick and label not in QUICK_MVU:
                continue
            ok, log, t = self.icarus("tb_mvu", MVU + ["tb/integration/tb_mvu.sv"], params, tag=f"mvu_{label}")
            self.record(f"mvu_{label}", ok, t, self.first_line(log, ok), "icarus")
            if ok:
                self.grab_perf(f"mvu_{label}", log)
        # 256 neurons x ~29k cycles per step is slow in Icarus: short trace here,
        # the full 700-step trace runs under Verilator below.
        for label, params in (("serial", {"ENGINE_SYSTOLIC": 0}), ("4x4_banked_wbuf2", {})):
            params = dict(params, TRACE='"tests/vectors/fly_trace_short.txt"')
            ok, log, t = self.icarus("tb_fly_core", PKG + MVU + NEURAL + ["tb/integration/tb_fly_core.sv"],
                                     params, tag=f"fly_{label}")
            self.record(f"fly_core_{label}", ok, t, self.first_line(log, ok), "icarus")
            if ok:
                self.grab_perf(f"fly_core_{label}", log)

    def stage_verilator(self):
        if not which("verilator"):
            print("\n== Verilator not found: assertion and long end-to-end runs skipped")
            return
        print(f"\n== Verilator + SVA ({tool_version(['verilator', '--version'])})")
        for label, params in (("serial", {"USE_SERIAL": 1}), ("4x4_banked_wbuf2", {}),
                              ("2x8_banked_wbuf2", {"ROWS": 2, "COLS": 8}),
                              ("4x4_simple_wbuf1", {"BANKED": 0, "WBUF": 1})):
            ok, log, t = self.verilator("tb_mvu", MVU + SVA[:2] + ["tb/integration/tb_mvu.sv"], params,
                                        tag=f"mvu_{label}")
            self.record(f"sva_mvu_{label}", ok, t, self.first_line(log, ok), "verilator")
        for label, params in (("4x4_banked_wbuf2", {}), ("serial", {"ENGINE_SYSTOLIC": 0}),
                              ("2x2_banked_wbuf2", {"ROWS": 2, "COLS": 2}),
                              ("4x4_simple_wbuf1", {"BANKED": 0, "WBUF": 1}),
                              ("8x8_banked_wbuf2", {"ROWS": 8, "COLS": 8})):
            if self.args.quick and label not in ("4x4_banked_wbuf2", "serial"):
                continue
            ok, log, t = self.verilator("tb_fly_core", PKG + MVU + NEURAL + SVA +
                                        ["tb/integration/tb_fly_core.sv"], params, tag=f"fly_{label}")
            self.record(f"sva_fly_core_{label}", ok, t, self.first_line(log, ok), "verilator")
            if ok:
                self.grab_perf(f"fly_core_{label}", log)
        for label, period, drops, probe in (("nodrop", 40000, "none", 0), ("drops", 3000, "some", 29)):
            out = BUILD / f"tel_{label}.txt"
            ok, log, t = self.verilator(
                "tb_telemetry_e2e", PKG + MVU + NEURAL + UART + SVA + ["tb/integration/tb_telemetry_e2e.sv"],
                {"PERIOD": period, "NSTEPS": 700, "PROBE": probe, "BYTES_OUT": f'"{out}"'},
                tag=f"tel_{label}")
            if ok:
                rc, clog, t2 = self.sh([sys.executable, "tests/check_telemetry.py", str(out),
                                        "tests/vectors/fly_trace.txt", "--probe", str(probe),
                                        "--cycles", str(NEURAL_CYCLES), "--drops", drops])
                ok, log, t = rc == 0, clog, t + t2
            self.record(f"telemetry_e2e_{label}", ok, t, self.first_line(log, ok), "verilator")
        out = BUILD / "top_bytes.txt"
        ok, log, t = self.verilator("tb_basys3_top", ALL_RTL + SVA + ["tb/integration/tb_basys3_top.sv"],
                                    {"BYTES_OUT": f'"{out}"'}, tag="top")
        if ok:
            logf = BUILD / "top.log"
            logf.write_text(log)
            rc1, l1, _ = self.sh([sys.executable, "tests/check_top_state.py", str(logf)])
            rc2, l2, _ = self.sh([sys.executable, "tests/check_stream.py", str(out),
                                  "--min-packets", "60", "--resets", "1"])
            ok = rc1 == 0 and rc2 == 0
            log = log + l1 + l2
            detail = (l1.strip() + " | " + l2.strip())
        else:
            detail = self.first_line(log, ok)
        self.record("basys3_top_smoke", ok, t, detail, "verilator")

    def stage_mutants(self):
        print("\n== Mutation checks (each injected bug must be detected)")
        mroot = BUILD / "mutant"
        for name, f, orig, repl, key, desc in MUTANTS:
            if mroot.exists():
                shutil.rmtree(mroot)
            for d in ("rtl", "tb", "tests"):
                shutil.copytree(ROOT / d, mroot / d)
            src = (mroot / f).read_text()
            if orig not in src:
                self.record(f"mutant_{name}", False, 0, "STALE pattern", "-")
                continue
            (mroot / f).write_text(src.replace(orig, repl, 1))
            t0 = time.time()
            if key == "mvu_4x4":
                ok, log, _ = self.icarus("tb_mvu", MVU + ["tb/integration/tb_mvu.sv"], {}, root=mroot, tag="mut")
            elif key == "mvu_2x8":
                ok, log, _ = self.icarus("tb_mvu", MVU + ["tb/integration/tb_mvu.sv"],
                                         {"ROWS": 2, "COLS": 8}, root=mroot, tag="mut")
            elif key == "mvu_serial":
                ok, log, _ = self.icarus("tb_mvu", MVU + ["tb/integration/tb_mvu.sv"],
                                         {"USE_SERIAL": 1}, root=mroot, tag="mut")
            elif key == "sva_mvu_4x4":
                ok, log, _ = self.verilator("tb_mvu", MVU + SVA[:2] + ["tb/integration/tb_mvu.sv"],
                                            {}, root=mroot, tag="mut")
            elif key == "lif":
                ok, log, _ = self.icarus("tb_lif", ["rtl/neural/lif_update.sv", "rtl/neural/lif_pipe.sv", "tb/unit/tb_lif.sv"],
                                         {}, root=mroot, tag="mut")
            elif key == "fly_core":
                ok, log, _ = self.verilator("tb_fly_core", PKG + MVU + NEURAL + ["tb/integration/tb_fly_core.sv"],
                                            {}, root=mroot, tag="mut", sva=False)
            elif key == "sva_fly_core":
                ok, log, _ = self.verilator("tb_fly_core", PKG + MVU + NEURAL + SVA +
                                            ["tb/integration/tb_fly_core.sv"], {}, root=mroot, tag="mut")
            elif key == "world":
                ok, log, _ = self.icarus("tb_fly_world", WORLD_TB, {}, root=mroot, tag="mut")
            elif key == "uart":
                ok, log, _ = self.icarus("tb_uart_tx", ["rtl/uart/uart_tx.sv", "tb/unit/tb_uart_tx.sv"],
                                         {}, root=mroot, tag="mut")
            elif key == "telemetry":
                out = BUILD / "tel_mut.txt"
                ok, log, _ = self.verilator(
                    "tb_telemetry_e2e", PKG + MVU + NEURAL + UART + ["tb/integration/tb_telemetry_e2e.sv"],
                    {"PERIOD": 40000, "NSTEPS": 200, "PROBE": 0, "BYTES_OUT": f'"{out}"'},
                    root=mroot, tag="mut", sva=False)
                if ok:
                    rc, clog, _ = self.sh([sys.executable, "tests/check_telemetry.py", str(out),
                                           "tests/vectors/fly_trace.txt", "--probe", "0",
                                           "--cycles", str(NEURAL_CYCLES), "--drops", "none"])
                    ok, log = rc == 0, clog
            else:
                raise ValueError(key)
            detected = not ok and not log.startswith("COMPILE")
            why = "compile error (mutant invalid)" if log.startswith("COMPILE") else \
                ("NOT detected" if ok else self.first_line(log, False))
            self.record(f"mutant_{name}", detected, time.time() - t0, f"{desc} -> {why}", key)

    # ---------------- report ----------------
    def write_report(self):
        REPORT.mkdir(parents=True, exist_ok=True)
        env = dict(
            date=datetime.datetime.now().isoformat(timespec="seconds"),
            host=platform.node(), platform=platform.platform(),
            wsl=("microsoft" in platform.release().lower()),
            python=sys.version.split()[0],
            iverilog=tool_version(["iverilog", "-V"]) if which("iverilog") else "not found",
            verilator=tool_version(["verilator", "--version"]) if which("verilator") else "not found",
            git=self.git_rev(),
        )
        npass = sum(r["status"] == "PASS" for r in self.results)
        summary = dict(environment=env, passed=npass, total=len(self.results),
                       results=self.results, perf=self.perf)
        (REPORT / "summary.json").write_text(json.dumps(summary, indent=2))
        lines = [f"# Regression summary", "",
                 f"- Date: {env['date']}", f"- Host: `{env['host']}` ({env['platform']})",
                 f"- Python {env['python']}; {env['iverilog']}; {env['verilator']}",
                 f"- Source revision: {env['git']}",
                 f"- Vector seeds: MVU 20260930, LIF 11, trace scenario fixed; tb_mvu seed 1",
                 f"- **{npass} / {len(self.results)} passed**", "",
                 "| Test | Simulator | Result | Time (s) | Detail |", "|---|---|---|---|---|"]
        for r in self.results:
            d = r["detail"].replace("|", "/")
            lines.append(f"| {r['name']} | {r['sim']} | {r['status']} | {r['seconds']} | {d} |")
        if self.perf:
            lines += ["", "## Cycle counts (simulation, no output stalls)", "", "```"] + self.perf + ["```"]
        (REPORT / "summary.md").write_text("\n".join(lines) + "\n")
        print(f"\n{npass}/{len(self.results)} passed. Report: {REPORT / 'summary.md'}")
        return npass == len(self.results)

    def git_rev(self):
        rc, out, _ = self.sh(["git", "rev-parse", "--short", "HEAD"])
        if rc != 0:
            return "uncommitted working tree (no git HEAD)"
        rc2, st, _ = self.sh(["git", "status", "--porcelain"])
        return out.strip() + (" + uncommitted changes" if st.strip() else "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mutants", action="store_true")
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--only", choices=("python", "icarus", "verilator", "mutants"))
    args = ap.parse_args()
    os.chdir(ROOT)
    r = Runner(args)
    if args.only in (None, "python"):
        r.stage_python()
    if args.only in (None, "icarus"):
        r.stage_icarus()
    if args.only in (None, "verilator"):
        r.stage_verilator()
    if args.mutants or args.only == "mutants":
        r.stage_mutants()
    sys.exit(0 if r.write_report() else 1)


if __name__ == "__main__":
    main()
