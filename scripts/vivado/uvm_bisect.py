#!/usr/bin/env python3
"""Find which construct in tb/uvm/mvu_uvm_pkg.sv crashes XSim's elaborator.

Run from the repository root with Vivado's settings64.sh sourced:
    python3 scripts/vivado/uvm_bisect.py

Phase 1 compiles the package cumulatively, one top-level class at a time (the
classes are in dependency order), and reports the first class whose addition
makes xelab crash (SIGSEGV), as opposed to compiling or reporting a normal error.
Phase 2 removes one method/covergroup at a time from that class and reports
which removal makes the crash disappear.

Results: build/xsim/bisect/report.txt (and the console).
"""

import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
PKG = ROOT / "tb" / "uvm" / "mvu_uvm_pkg.sv"
WORK = ROOT / "build" / "xsim" / "bisect"

TOP = """`timescale 1ns/1ps
module bisect_top;
    import uvm_pkg::*;
    import mvu_uvm_pkg::*;
    logic clk = 0;
    mvu_if #(.N_MAX(64)) vif (clk);
    initial run_test();
endmodule
"""
IFACE = ROOT / "tb" / "uvm" / "mvu_if.sv"
RTL = ["rtl/core/systolic_pe.sv", "rtl/core/systolic_array.sv", "rtl/core/weight_memory.sv",
       "rtl/core/mvu_systolic.sv", "rtl/core/mvu_serial.sv"]
SVA = ["tb/sva/mvu_sva.sv", "tb/sva/mvu_binds.sv"]
UVM_TOP = ["tb/uvm/mvu_if.sv", "tb/uvm/mvu_uvm_pkg.sv", "tb/uvm/tb_uvm_top.sv"]


def run_files(files, top, tag):
    """Compile real repository files (absolute paths) and elaborate `top`."""
    d = WORK / tag
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    r = subprocess.run(["xvlog", "-sv", "-L", "uvm", *[str(ROOT / f) for f in files]], cwd=d,
                       capture_output=True, text=True)
    if r.returncode != 0:
        return "COMPILE-ERROR", r.stdout + r.stderr
    r = subprocess.run(["xelab", "-L", "uvm", "--timescale", "1ns/1ps", top, "-s", "sim"],
                       cwd=d, capture_output=True, text=True)
    out = r.stdout + r.stderr
    (d / "xelab.out").write_text(out)
    if "SIGSEGV" in out or "Signal SIG" in out:
        return "CRASH", out
    return ("OK" if r.returncode == 0 else "ELAB-ERROR"), out


def classify(pkg_text, tag):
    d = WORK / tag
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    (d / "pkg.sv").write_text(pkg_text)
    (d / "top.sv").write_text(TOP)
    r = subprocess.run(["xvlog", "-sv", "-L", "uvm", str(IFACE), "pkg.sv", "top.sv"], cwd=d,
                       capture_output=True, text=True)
    (d / "xvlog.out").write_text(r.stdout + r.stderr)
    if r.returncode != 0:
        return "COMPILE-ERROR", (r.stdout + r.stderr)
    r = subprocess.run(["xelab", "-L", "uvm", "--timescale", "1ns/1ps", "bisect_top", "-s", "sim"],
                       cwd=d, capture_output=True, text=True)
    out = r.stdout + r.stderr
    (d / "xelab.out").write_text(out)
    if "SIGSEGV" in out or "Signal SIG" in out:
        return "CRASH", out
    return ("OK" if r.returncode == 0 else "ELAB-ERROR"), out


def first_error(out):
    for line in out.splitlines():
        if "ERROR" in line:
            return line.strip()[:160]
    return ""


def main():
    if not shutil.which("xelab"):
        sys.exit("xelab not on PATH: source /opt/AMD/2025.2/Vivado/settings64.sh first")
    text = PKG.read_text()
    lines = text.splitlines(keepends=True)
    starts = [i for i, l in enumerate(lines) if re.match(r"^    class \w+", l)]
    end_pkg = max(i for i, l in enumerate(lines) if l.startswith("endpackage"))
    pre = "".join(lines[:starts[0]])
    chunks = []
    for k, s in enumerate(starts):
        e = starts[k + 1] if k + 1 < len(starts) else end_pkg
        name = re.match(r"^    class (\w+)", lines[s]).group(1)
        chunks.append((name, "".join(lines[s:e])))

    WORK.mkdir(parents=True, exist_ok=True)
    report = []

    def log(msg):
        print(msg, flush=True)
        report.append(msg)

    log(f"Package: {PKG} ({len(chunks)} classes)")
    log("== Phase 0: real file sets")
    for tag, files in (("full (RTL + SVA binds + UVM)", RTL + SVA + UVM_TOP),
                       ("without SVA files", RTL + UVM_TOP)):
        st, out = run_files(files, "tb_uvm_top", "p0_" + tag.split()[0])
        log(f"  {tag:32} {st}  {first_error(out) if st not in ('OK', 'CRASH') else ''}")
    log("== Phase 1: cumulative classes (package + interface, stub top)")
    st, out = classify(pre + "endpackage\n", "p1_00_preamble")
    log(f"  {'(typedefs only)':28} {st}  {first_error(out) if st != 'OK' else ''}")
    culprit = None
    for k, (name, _) in enumerate(chunks):
        body = pre + "".join(c for _, c in chunks[:k + 1]) + "endpackage\n"
        st, out = classify(body, f"p1_{k + 1:02d}_{name}")
        log(f"  + {name:26} {st}  {first_error(out) if st not in ('OK', 'CRASH') else ''}")
        if st == "CRASH":
            culprit = k
            break
    if culprit is None:
        log("No crash reproduced with the package alone; the crash needs the DUT/top. "
            "Next: compile tb_uvm_top without the DUT.")
        (WORK / "report.txt").write_text("\n".join(report) + "\n")
        return

    name, chunk = chunks[culprit]
    log(f"== Phase 2: inside class {name}")
    # members at 8-space indentation: functions, tasks, covergroups, constraints
    members = []
    clines = chunk.splitlines(keepends=True)
    i = 0
    while i < len(clines):
        m = re.match(r"^        (?:virtual |local |protected |static |extern )*"
                     r"(function|task|covergroup|constraint)\b", clines[i])
        if m:
            kind = m.group(1)
            endkw = {"function": "endfunction", "task": "endtask", "covergroup": "endgroup"}.get(kind)
            j = i
            if endkw:
                while j < len(clines) and not clines[j].startswith("        " + endkw):
                    j += 1
            else:                       # constraint: single line or until a line ending with '}'
                while j < len(clines) and not clines[j].rstrip().endswith("}"):
                    j += 1
            members.append((i, j, clines[i].strip()[:70]))
            i = j + 1
        else:
            i += 1
    prefix = pre + "".join(c for _, c in chunks[:culprit])
    for (a, b, label) in members:
        variant = "".join(clines[:a] + clines[b + 1:])
        st, out = classify(prefix + variant + "endpackage\n", f"p2_{a:03d}")
        verdict = "removing this STOPS the crash" if st != "CRASH" else "still crashes"
        log(f"  - {label:70} {st:13} {verdict}")
    (WORK / "report.txt").write_text("\n".join(report) + "\n")
    log(f"\nReport: {WORK / 'report.txt'}")


if __name__ == "__main__":
    main()
