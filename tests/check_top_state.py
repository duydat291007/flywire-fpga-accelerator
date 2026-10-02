#!/usr/bin/env python3
"""Compare the STATE line printed by tb_basys3_top with the reference model.

The board test runs PAUSED_STEPS single steps with food absent, then food
present for every later step. Usage: check_top_state.py LOG [--paused 3]
"""
import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "model"))
from fly_model.world import FlySim          # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("log")
ap.add_argument("--paused", type=int, default=3)
a = ap.parse_args()
m = re.search(r"STATE step=(\d+) fly=(\d+),(\d+) heading=(\d+) food=(\d+),(\d+) eaten=(\d+) lfsr=(\d+)",
              pathlib.Path(a.log).read_text())
if not m:
    sys.exit("FAIL check_top_state: no STATE line")
step, fx, fy, hd, gx, gy, eaten, lfsr = map(int, m.groups())
sim = FlySim()
for t in range(step):
    sim.world.food_present = t >= a.paused
    sim.step()
w = sim.world
got = (fx, fy, hd, gx, gy, eaten, lfsr)
exp = (*w.fly, w.heading, *w.food, w.eaten, w.lfsr)
ok = got == exp
print(f"{'PASS' if ok else 'FAIL'} check_top_state: step {step}, rtl {got}, model {exp}")
sys.exit(0 if ok else 1)
