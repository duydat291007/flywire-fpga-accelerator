#!/usr/bin/env python3
"""Collect Vivado build summaries into reports/impl/results.md (and .csv).

Combines each build's post-route resources and timing (build/vivado/*/summary.txt,
written by scripts/vivado/build.tcl) with the cycle counts measured in simulation
(reports/regression/summary.json, PERF lines) to give time per operation.

Time per operation is computed at the CONSTRAINED clock (100 MHz) and only
reported when post-route setup and hold slack are non-negative; otherwise the
row is marked "timing not met". No theoretical peak rates are reported.
"""

import csv
import json
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILDS = ROOT / "build" / "vivado"
OUT = ROOT / "reports" / "impl"

# simulation label for each Vivado config (MVU dim-64 op, neural update)
SIM_LABEL = {
    "serial": "serial", "sys2x2_simple": "2x2_simple_wbuf1", "sys2x2_banked": "2x2_banked_wbuf2",
    "sys4x4_simple": "4x4_simple_wbuf1", "sys4x4_banked": "4x4_banked_wbuf1",
    "sys4x4_banked_wbuf2": "4x4_banked_wbuf2", "sys4x4_banked_wbuf3": "4x4_banked_wbuf3",
    "sys8x8_banked_wbuf2": "8x8_banked_wbuf2",
}


def sim_cycles():
    js = ROOT / "reports" / "regression" / "summary.json"
    if not js.exists():
        return {}, {}
    perf = json.loads(js.read_text()).get("perf", [])
    mvu, neural = {}, {}
    for line in perf:
        m = re.match(r"mvu_(\S+): PERF case=\d+ dim=64 stall=0 cycles=(\d+)", line)
        if m:
            mvu[m.group(1)] = int(m.group(2))
        m = re.match(r"fly_core_(\S+): PERF neural_update \[.*\] cycles_min=(\d+)", line)
        if m:
            neural[m.group(1)] = int(m.group(2))
    return mvu, neural


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    mvu, neural = sim_cycles()
    rows = []
    for s in sorted(BUILDS.glob("*/summary.txt")):
        d = dict(l.split("=", 1) for l in s.read_text().split("\n") if "=" in l)
        cfg = d.get("config", "?")
        met = all(float(d.get(k, "-1") or -1) >= 0 for k in ("wns_ns", "whs_ns"))
        lab = SIM_LABEL.get(cfg)
        cyc = mvu.get(lab) if d.get("target") == "mvu" else neural.get(lab)
        rows.append(dict(
            target=d.get("target"), config=cfg, vivado=d.get("vivado"), part=d.get("part"),
            LUT=d.get("lut"), FF=d.get("ff"), DSP=d.get("dsp"), BRAM_tiles=d.get("bram"),
            LUTRAM=d.get("lutram"), WNS_ns=d.get("wns_ns"), WHS_ns=d.get("whs_ns"),
            timing="met @100MHz" if met else "NOT MET",
            cycles=cyc if cyc else "",
            time_us=f"{cyc / 100:.2f}" if (cyc and met) else ("timing not met" if cyc else "")))
        # keep the key reports next to the summary table
        dst = OUT / s.parent.name
        dst.mkdir(exist_ok=True)
        for rpt in ("failing_endpoints.txt", "logic_levels.rpt", "utilization.rpt", "timing_summary.rpt", "check_timing.rpt",
                    "power_ESTIMATE.rpt", "methodology.rpt", "critical_paths.rpt", "summary.txt"):
            if (s.parent / rpt).exists():
                shutil.copy(s.parent / rpt, dst / rpt)
    if not rows:
        print("no Vivado builds found under build/vivado")
        return
    keys = list(rows[0].keys())
    with open(OUT / "results.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)
    md = ["# Vivado implementation results", "",
          "Post-route numbers from scripts/vivado/build.tcl. `mvu` rows: the matrix-vector unit alone, "
          "out of context (only reg-to-reg paths are meaningful). `top` rows: the full board design. "
          "Cycles: simulation, 64x64 operation (mvu) or one neural update (top), no output stalls. "
          "Time = cycles / 100 MHz, shown only when post-route timing is met. Power reports in the "
          "per-build folders are Vivado ESTIMATES.", "",
          "| " + " | ".join(keys) + " |", "|" + "---|" * len(keys)]
    md += ["| " + " | ".join(str(r[k]) for k in keys) + " |" for r in rows]
    (OUT / "results.md").write_text("\n".join(md) + "\n")
    print(f"wrote {OUT / 'results.md'} ({len(rows)} builds)")


if __name__ == "__main__":
    main()
