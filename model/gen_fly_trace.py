#!/usr/bin/env python3
"""Generate a closed-loop reference trace for tb_fly_core (FlyWire network, world v2).

tests/vectors/fly_trace.txt
    <num_steps>
    per step, one line:
      food_present threat_present respawn_food respawn_threat          (inputs for this step)
      step lfsr fly_x fly_y heading food_x food_y threat_x threat_y
      eaten caught jumps last_action m0..m5 spikes_hex V0 .. V255       (state after the step)

The scenario uses the food and threat buttons repeatedly so the sugar ->
proboscis (eat) and looming -> giant fiber (jump) pathways, wall handling,
pursuit and catches are all exercised. Coverage of each world rule is printed
and checked, so a scenario that stops exercising a rule fails loudly.
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from fly_model.world import FlySim          # noqa: E402


def scenario_short(n_steps):
    """Short scenario for slow simulators: an early meal and an early escape."""
    for t in range(n_steps):
        yield int(t < 30), int(t >= 26), int(t == 0), int(t == 26)


def scenario(n_steps):
    """Yield (food, threat, press_food, press_threat) per step."""
    for t in range(n_steps):
        food = 30 <= t < 260 or t >= 420
        threat = 140 <= t < 420 or (t >= 520 and (t // 60) % 2 == 0)
        rf = t in (30, 90, 200, 201, 430, 470, 560)
        rt = t in (140, 220, 300, 360, 480, 521, 523, 640)
        yield int(food), int(threat), int(rf), int(rt)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=700)
    ap.add_argument("--out", default=str(pathlib.Path(__file__).resolve().parent.parent
                                         / "tests" / "vectors" / "fly_trace.txt"))
    ap.add_argument("--no-check", action="store_true", help="skip the coverage check")
    ap.add_argument("--short", action="store_true",
                    help="short scenario (tests/vectors/fly_trace_short.txt) for Icarus")
    args = ap.parse_args()
    if args.short:
        if args.steps == 700:
            args.steps = 44
        if args.out.endswith("fly_trace.txt"):
            args.out = args.out[:-len("fly_trace.txt")] + "fly_trace_short.txt"

    sim = FlySim()
    lines = [str(args.steps)]
    spikes_total = 0
    actions = [0] * 5
    for food, threat, rf, rt in (scenario_short if args.short else scenario)(args.steps):
        w = sim.world
        w.food_present, w.threat_present = bool(food), bool(threat)
        w.pending_food_respawn |= bool(rf)
        w.pending_threat_respawn |= bool(rt)
        wc = w.window_count
        sim.step()
        if wc == 7:
            actions[w.last_action] += 1
        bits = sum(b << i for i, b in enumerate(sim.s))
        spikes_total += sum(sim.s)
        lines.append(" ".join(map(str, [
            food, threat, rf, rt, sim.step_count, w.lfsr, *w.fly, w.heading, *w.food, *w.threat,
            w.eaten, w.caught, w.jumps, w.last_action, *w.last_motor, f"{bits:064x}", *sim.V])))
    path = pathlib.Path(args.out)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
    w = sim.world
    print(f"wrote {args.steps} steps to {path}: eaten={w.eaten} caught={w.caught} "
          f"jumps={w.jumps} actions(walk,back,jump,eat,blocked)={actions} spikes={spikes_total}")
    if not args.no_check:
        need = (("eat", w.eaten), ("jump", w.jumps)) if args.short else \
            (("eat", w.eaten), ("catch", w.caught), ("jump", w.jumps), ("blocked", actions[4]))
        missing = [n for n, v in need if not v]
        if missing:
            sys.exit(f"scenario no longer exercises: {missing}")


if __name__ == "__main__":
    main()
