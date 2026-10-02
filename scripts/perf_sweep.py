#!/usr/bin/env python3
"""Cycle-count sweep: identical workload on every MVU configuration.

Runs tb_mvu on tests/vectors/mvu_perf.txt (dims 1..64 without stalls, then
dim 64 with 25/50/75/90 % output stall probability) for each configuration
(Verilator if available, else Icarus), and writes reports/perf/mvu_cycles.md
and .json.

Measurement boundary: from the cycle the command is accepted to the cycle
`done` is asserted, inclusive of the result drain. Weight and input loading
through the write ports happens before the command and is NOT included (it is
the same for every configuration: 4096 + 64 transfers, or 4096 + 1 with the
binary bulk port). Internal weight movement from memory into the PEs IS included.
Every run also checks every result against the reference model.
"""

import json
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MVU = ["rtl/core/systolic_pe.sv", "rtl/core/systolic_array.sv", "rtl/core/weight_memory.sv",
       "rtl/core/mvu_systolic.sv", "rtl/core/mvu_serial.sv"]
CONFIGS = [
    ("serial", dict(USE_SERIAL=1), 1),
    ("2x2 simple wbuf1", dict(ROWS=2, COLS=2, BANKED=0, WBUF=1), 4),
    ("2x2 banked wbuf1", dict(ROWS=2, COLS=2, BANKED=1, WBUF=1), 4),
    ("2x2 banked wbuf2", dict(ROWS=2, COLS=2, BANKED=1, WBUF=2), 4),
    ("4x4 simple wbuf1", dict(ROWS=4, COLS=4, BANKED=0, WBUF=1), 16),
    ("4x4 simple wbuf2", dict(ROWS=4, COLS=4, BANKED=0, WBUF=2), 16),
    ("4x4 banked wbuf1", dict(ROWS=4, COLS=4, BANKED=1, WBUF=1), 16),
    ("4x4 banked wbuf2", dict(ROWS=4, COLS=4, BANKED=1, WBUF=2), 16),
    ("4x4 banked wbuf3", dict(ROWS=4, COLS=4, BANKED=1, WBUF=3), 16),
    ("4x4 banked wbuf4", dict(ROWS=4, COLS=4, BANKED=1, WBUF=4), 16),
    ("8x8 banked wbuf2", dict(ROWS=8, COLS=8, BANKED=1, WBUF=2), 64),
    ("8x8 banked wbuf4", dict(ROWS=8, COLS=8, BANKED=1, WBUF=4), 64),
]


def run(params, tag):
    vec = '"tests/vectors/mvu_perf.txt"'
    b = ROOT / "build" / "perf" / tag
    if b.exists():
        shutil.rmtree(b)
    b.mkdir(parents=True)
    if shutil.which("verilator"):
        cmd = ["verilator", "--binary", "--timing", "-Wno-fatal", "-Wno-lint", "-Wno-style",
               "-Mdir", str(b), "--top-module", "tb_mvu", "-o", "sim", f"-GVECTORS={vec}"]
        cmd += [f"-G{k}={v}" for k, v in params.items()] + MVU + ["tb/integration/tb_mvu.sv"]
        subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True)
        out = subprocess.run([str(b / "sim")], cwd=ROOT, capture_output=True, text=True).stdout
    else:
        cmd = ["iverilog", "-g2012", "-o", str(b / "sim.vvp"), "-s", "tb_mvu", f"-Ptb_mvu.VECTORS={vec}"]
        cmd += [f"-Ptb_mvu.{k}={v}" for k, v in params.items()] + MVU + ["tb/integration/tb_mvu.sv"]
        subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True)
        out = subprocess.run(["vvp", "-n", str(b / "sim.vvp")], cwd=ROOT, capture_output=True, text=True).stdout
    if "PASS" not in out:
        sys.exit(f"{tag}: functional failure\n{out[-1500:]}")
    res = {}
    for m in re.finditer(r"PERF case=\d+ dim=(\d+) stall=(\d+) cycles=(\d+)", out):
        res[(int(m.group(1)), int(m.group(2)))] = int(m.group(3))
    return res


def main():
    subprocess.run([sys.executable, "model/gen_mvu_vectors.py", "--perf"], cwd=ROOT, check=True,
                   capture_output=True)
    data = {}
    for name, params, pes in CONFIGS:
        data[name] = run(params, re.sub(r"\W+", "_", name))
        print(name, data[name].get((64, 0)), flush=True)
    dims = sorted({d for r in data.values() for (d, s) in r if s == 0})
    ser = data["serial"]
    md = ["# MVU cycle counts (simulation)", "",
          "Identical workload for every configuration; every result checked against the model. "
          "Cycles from command acceptance to `done`, including result drain, excluding the "
          "external weight/x load (same for all). Clock rate is not part of this table: see "
          "`reports/impl/results.md` for post-route timing.", "",
          "## Cycles per operation, no output stalls", "",
          "| Config | PEs | " + " | ".join(f"dim {d}" for d in dims) + " | speedup vs serial (dim 64) | useful MAC/cycle (dim 64) |",
          "|---|---|" + "---|" * len(dims) + "---|---|"]
    for name, params, pes in CONFIGS:
        r = data[name]
        c64 = r[(64, 0)]
        md.append(f"| {name} | {pes} | " + " | ".join(str(r[(d, 0)]) for d in dims) +
                  f" | {ser[(64, 0)] / c64:.2f}x | {4096 / c64:.2f} |")
    md += ["", "Useful MAC/cycle = 4096 multiply-accumulates / total cycles (drain included). "
           "An array of P PEs could at best reach P; weight bandwidth (1 or COLS weights per "
           "cycle) is the real bound for matrix-vector products (docs/architecture.md 2.4).", "",
           "## Output-stall overhead, dim 64", "",
           "| Config | 0 % | 25 % | 50 % | 75 % | 90 % | extra cycles at 50 % |", "|---|---|---|---|---|---|---|"]
    for name, _, _ in CONFIGS:
        r = data[name]
        row = [r.get((64, s), "") for s in (0, 25, 50, 75, 90)]
        md.append(f"| {name} | " + " | ".join(map(str, row)) + f" | {row[2] - row[0]} |")
    md += ["", "Stalls only lengthen the drain: all arithmetic finishes before the first result is "
           "offered, so overhead is independent of the engine and roughly dim × p/(1−p) cycles "
           "for stall probability p (random, deterministic seed)."]
    out = ROOT / "reports" / "perf"
    out.mkdir(parents=True, exist_ok=True)
    (out / "mvu_cycles.md").write_text("\n".join(md) + "\n")
    (out / "mvu_cycles.json").write_text(json.dumps(
        {n: {f"{d},{s}": c for (d, s), c in r.items()} for n, r in data.items()}, indent=1))
    print("wrote", out / "mvu_cycles.md")


if __name__ == "__main__":
    main()
