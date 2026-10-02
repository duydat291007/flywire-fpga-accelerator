#!/usr/bin/env python3
"""Closed-loop behaviour check of the FlyWire network in the reference world.

Scenarios (each from a different pseudo-random starting state):
  food   : press the food button (food appears ahead); success = the fly eats
           (proboscis motor neurons fire while the food is within taste range)
  threat : press the threat button (threat appears to one side, then pursues);
           success = not caught within the horizon
Each scenario also runs with every synapse removed (lesion control), which
shows how much of the behaviour comes from the FlyWire connections.

The neural update here uses numpy for speed; the script first checks that it
matches the plain-Python reference model (fly_model.world.FlySim) step for
step, so the numbers describe exactly what the RTL must reproduce.

Writes model/flywire/out/behavior_report.md.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from fly_model import constants as C, network as net          # noqa: E402
from fly_model.world import World, FlySim                    # noqa: E402

N_TRIALS = 40
WANDER = 400
HORIZON = 320


class FastSim:
    def __init__(self, W, threshold=net.THRESHOLD):
        self.W = np.array(W, dtype=np.int64)
        self.th = threshold
        self.w = World()
        self.V = np.zeros(C.N_NEURONS, np.int64)
        self.s = np.zeros(C.N_NEURONS, np.int64)

    def step(self):
        u = np.array(self.w.sensors(), dtype=np.int64)
        c = (15 * self.V) // 16 + self.W @ self.s + u
        self.s = (c >= self.th).astype(np.int64)
        self.V = np.where(self.s == 1, 0, np.maximum(c, 0))
        self.w.update(self.s.tolist())


def equivalence(W, steps=300):
    ref, fast = FlySim(weights=W), FastSim(W)
    for sim in (ref, fast):
        sim_w = sim.world if hasattr(sim, "world") else sim.w
        sim_w.food_present = sim_w.threat_present = True
        sim_w.food, sim_w.threat = [30, 30], [40, 36]
    for t in range(steps):
        ref.step()
        fast.step()
        assert list(fast.V) == ref.V and list(fast.s) == ref.s, f"diverged at step {t}"
        assert fast.w == ref.world, f"world diverged at step {t}"


def trials(W, kind):
    ok, lat = 0, []
    for k in range(N_TRIALS):
        S = FastSim(W)
        S.w.lfsr = ((0xACE1 * (k + 1)) & 0xFFFF) or 1
        for _ in range(WANDER + 37 * k):
            S.step()
        if kind == "food":
            S.w.food_present, S.w.threat_present = True, False
            S.w.pending_food_respawn = True
            e0 = S.w.eaten
            for t in range(HORIZON):
                S.step()
                if S.w.eaten > e0:
                    ok += 1
                    lat.append(t)
                    break
        else:
            S.w.food_present, S.w.threat_present = False, True
            S.w.pending_threat_respawn = True
            c0, j0, first = S.w.caught, S.w.jumps, None
            for t in range(HORIZON):
                S.step()
                if first is None and S.w.jumps > j0:
                    first = t
            ok += S.w.caught == c0
            if first is not None:
                lat.append(first)
    return ok, (int(np.median(lat)) if lat else None)


def main():
    W = net.build_weights()
    equivalence(W)
    Z = [[0] * C.N_NEURONS for _ in range(C.N_NEURONS)]
    rows = []
    for kind, what, latname in (("food", "ate the food", "steps to eating"),
                                ("threat", "escaped (not caught)", "steps to first jump")):
        a, la = trials(W, kind)
        b, lb = trials(Z, kind)
        rows.append((kind, what, a, b, latname, la, lb))
    out = os.path.join(os.path.dirname(__file__), "out", "behavior_report.md")
    with open(out, "w") as f:
        f.write("# Closed-loop behaviour of the FlyWire network (reference model)\n\n")
        f.write(f"{N_TRIALS} trials per scenario, horizon {HORIZON} timesteps "
                f"({HORIZON // C.MOVE_WINDOW} motor windows). Weight scale {net.SCALE}, "
                f"threshold {net.THRESHOLD}. Fast simulator verified step-for-step "
                "against fly_model.world.FlySim.\n\n")
        f.write("| scenario | success | FlyWire circuit | all synapses removed | median latency (circuit) |\n")
        f.write("|---|---|---|---|---|\n")
        for kind, what, a, b, latname, la, lb in rows:
            f.write(f"| {kind} | {what} | {a}/{N_TRIALS} | {b}/{N_TRIALS} | {la} {latname} |\n")
        f.write("\nLesioned fly: sensors still receive input, but nothing propagates, so it never "
                "feeds or jumps; its escapes come only from the default walk.\n")
    print(open(out).read())


if __name__ == "__main__":
    main()
