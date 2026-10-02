#!/usr/bin/env python3
"""Pre-Vivado resource ESTIMATES with Yosys synth_xilinx (7-series cell library).

These numbers are not Vivado results: Yosys maps to different heuristics, has
no placement/routing, and reports no timing. They are useful only to compare
configurations of the same RTL against each other before Vivado is available.
Vivado results (scripts/vivado/build.tcl) supersede them.

Requires: yosys (0.33+) and sv2v (https://github.com/zachjs/sv2v) on PATH or
--sv2v PATH. Writes reports/yosys/estimates.md and estimates.json.
"""

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "yosys"
REP = ROOT / "reports" / "yosys"

MVU = ["rtl/core/systolic_pe.sv", "rtl/core/systolic_array.sv", "rtl/core/weight_memory.sv",
       "rtl/core/mvu_systolic.sv", "rtl/core/mvu_serial.sv"]
ALL = ["rtl/common/fly_cfg_pkg.sv"] + MVU + [
    "rtl/neural/lif_update.sv", "rtl/neural/lif_pipe.sv", "rtl/neural/fly_world.sv", "rtl/neural/fly_core.sv",
    "rtl/uart/uart_tx.sv", "rtl/uart/telemetry.sv",
    "rtl/board/input_conditioner.sv", "rtl/board/basys3_top.sv"]

CONFIGS = [  # name, top, params
    ("mvu serial", "mvu_serial", {}),
    ("mvu 2x2 simple wbuf1", "mvu_systolic", dict(ROWS=2, COLS=2, BANKED=0, WBUF=1)),
    ("mvu 2x2 banked wbuf2", "mvu_systolic", dict(ROWS=2, COLS=2, BANKED=1, WBUF=2)),
    ("mvu 4x4 simple wbuf1", "mvu_systolic", dict(ROWS=4, COLS=4, BANKED=0, WBUF=1)),
    ("mvu 4x4 banked wbuf1", "mvu_systolic", dict(ROWS=4, COLS=4, BANKED=1, WBUF=1)),
    ("mvu 4x4 banked wbuf2", "mvu_systolic", dict(ROWS=4, COLS=4, BANKED=1, WBUF=2)),
    ("mvu 4x4 banked wbuf3", "mvu_systolic", dict(ROWS=4, COLS=4, BANKED=1, WBUF=3)),
    ("mvu 8x8 banked wbuf2", "mvu_systolic", dict(ROWS=8, COLS=8, BANKED=1, WBUF=2)),
    ("basys3_top serial", "basys3_top", dict(ENGINE_SYSTOLIC=0)),
    ("basys3_top 4x4 banked wbuf2", "basys3_top", dict(ENGINE_SYSTOLIC=1)),
]


def stat(log):
    cells = dict(re.findall(r"^\s+(\w+)\s+(\d+)\s*$", log.split("Printing statistics")[-1], re.M))
    cells = {k: int(v) for k, v in cells.items()}
    luts = sum(v for k, v in cells.items() if re.fullmatch(r"LUT\d", k))
    ffs = sum(v for k, v in cells.items() if re.fullmatch(r"FD\w+", k))
    lutram = sum(v for k, v in cells.items() if k.startswith(("RAM32", "RAM64", "RAM128", "RAM256")))
    srl = sum(v for k, v in cells.items() if k.startswith("SRL"))
    return dict(LUT=luts, FF=ffs, DSP48E1=cells.get("DSP48E1", 0),
                RAMB18=cells.get("RAMB18E1", 0), RAMB36=cells.get("RAMB36E1", 0),
                LUTRAM_cells=lutram, SRL=srl, CARRY4=cells.get("CARRY4", 0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sv2v", default=shutil.which("sv2v") or "/tmp/sv2v-Linux/sv2v")
    a = ap.parse_args()
    if not shutil.which("yosys") or not pathlib.Path(a.sv2v).exists():
        sys.exit("need yosys and sv2v")
    OUT.mkdir(parents=True, exist_ok=True)
    REP.mkdir(parents=True, exist_ok=True)
    v = OUT / "all.v"
    with open(v, "w") as f:
        subprocess.run([a.sv2v, *[str(ROOT / s) for s in ALL]], stdout=f, check=True, cwd=ROOT)
    ver = subprocess.run(["yosys", "-V"], capture_output=True, text=True).stdout.strip()
    rows = []
    for name, top, params in CONFIGS:
        tag = re.sub(r"\W+", "_", name)
        ys = OUT / f"{tag}.ys"
        chp = " ".join(f"-set {k} {val}" for k, val in params.items())
        ys.write_text(f"read_verilog {v}\n" + (f"chparam {chp} {top}\n" if chp else "") +
                      f"synth_xilinx -family xc7 -top {top} -flatten\nstat\n")
        # cwd = rtl/common so $readmemh("network_weights.mem") resolves
        p = subprocess.run(["yosys", "-q", "-l", str(OUT / f"{tag}.log"), str(ys)], cwd=ROOT / "rtl" / "common",
                           capture_output=True, text=True)
        if p.returncode != 0:
            print("FAIL", name, p.stderr[-500:])
            continue
        s = stat((OUT / f"{tag}.log").read_text())
        rows.append(dict(config=name, **s))
        print(name, s, flush=True)
    (REP / "estimates.json").write_text(json.dumps(dict(tool=ver, rows=rows), indent=2))
    hdr = ["config", "LUT", "FF", "DSP48E1", "RAMB18", "RAMB36", "LUTRAM_cells", "SRL", "CARRY4"]
    md = ["# Yosys resource ESTIMATES (not Vivado results)", "",
          f"Tool: {ver}, `synth_xilinx -family xc7 -flatten`, RTL converted with sv2v. "
          "No placement, routing, or timing. MVU rows are the unit alone; basys3_top rows "
          "are the whole design. Device capacity (XC7A35T): 20,800 LUT, 41,600 FF, 90 DSP, "
          "50 RAMB36 (100 RAMB18).", "",
          "| " + " | ".join(hdr) + " |", "|" + "---|" * len(hdr)]
    for r in rows:
        md.append("| " + " | ".join(str(r[h]) for h in hdr) + " |")
    (REP / "estimates.md").write_text("\n".join(md) + "\n")
    print("wrote", REP / "estimates.md")


if __name__ == "__main__":
    main()
