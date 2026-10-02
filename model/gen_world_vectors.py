#!/usr/bin/env python3
"""Random-stimulus vectors for the world alone (tb_fly_world).

The closed-loop trace exercises the world only in the situations the real
network produces (for example, the fly almost always escapes, so catches by
pursuit are rare). Here the output-neuron spikes are random, so every world
rule - jumps at walls, catches, eating, steering, backing up, pursuit, button
placements - is exercised many times.

tests/vectors/world_vectors.txt
    <num_steps>
    per step: food threat press_food press_threat out_spikes_hex(24 bits: neurons 232..255)
              uFL uFR uTL uTR (expected sensors BEFORE the update)
              lfsr fly_x fly_y heading food_x food_y threat_x threat_y eaten caught jumps
              last_action window_count m0..m5                         (state AFTER the update)
"""

import argparse
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from fly_model import constants as C          # noqa: E402
from fly_model.world import World            # noqa: E402

OUT0 = 232


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=6000)
    ap.add_argument("--seed", type=int, default=20261001)
    ap.add_argument("--out", default=str(pathlib.Path(__file__).resolve().parent.parent
                                         / "tests" / "vectors" / "world_vectors.txt"))
    a = ap.parse_args()
    rng = random.Random(a.seed)
    w = World()
    lines = [str(a.steps)]
    food = threat = False
    # per-group firing probabilities, re-drawn every few hundred steps
    probs = None
    actions = [0] * 5
    for t in range(a.steps):
        if t % 300 == 0:
            probs = dict(gf=rng.choice([0.0, 0.002, 0.02]), esc=rng.random() * 0.3,
                         mdn=rng.random() * 0.5, fwd=rng.random() * 0.5,
                         stl=rng.random() * 0.5, str_=rng.random() * 0.5, feed=rng.random() * 0.5)
        if rng.random() < 0.01:
            food = not food
        if rng.random() < 0.01:
            threat = not threat
        rf = rng.random() < 0.02
        rt = rng.random() < 0.02
        w.food_present, w.threat_present = food, threat
        w.pending_food_respawn |= rf
        w.pending_threat_respawn |= rt
        u = w.sensors()
        p = ([probs["gf"]] * 2 + [probs["esc"]] * 8 + [probs["mdn"]] * 4 + [probs["fwd"]] * 2 +
             [probs["stl"]] * 2 + [probs["str_"]] * 2 + [probs["feed"]] * 4)
        out = [int(rng.random() < q) for q in p]
        spikes = [0] * OUT0 + out
        wc = w.window_count
        w.update(spikes)
        if wc == C.MOVE_WINDOW - 1:
            actions[w.last_action] += 1
        bits = sum(b << i for i, b in enumerate(out))
        lines.append(" ".join(map(str, [
            int(food), int(threat), int(rf), int(rt), f"{bits:06x}", u[0], u[8], u[16], u[24],
            w.lfsr, *w.fly, w.heading, *w.food, *w.threat, w.eaten, w.caught, w.jumps,
            w.last_action, w.window_count, *w.last_motor])))
    path = pathlib.Path(a.out)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
    print(f"wrote {a.steps} world steps to {path}: eaten={w.eaten} caught={w.caught} jumps={w.jumps} "
          f"actions(walk,back,jump,eat,blocked)={actions}")
    if not all(actions) or not w.caught:
        sys.exit("world vectors do not exercise every action and a catch")


if __name__ == "__main__":
    main()
