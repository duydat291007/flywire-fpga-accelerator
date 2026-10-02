#!/usr/bin/env python3
"""Directed + random vectors for tb_lif: threshold equality, inhibition
clamping, leak flooring, extreme 32-bit network inputs, maximum V.

tests/vectors/lif_cases.txt:  <n> then lines "threshold v i u v_next spike"
"""
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from fly_model.reference import lif_update      # noqa: E402

THRESHOLDS = (100, 1, 65535)        # tb_lif is instantiated once per threshold


def cases(seed=11):
    rng = random.Random(seed)
    out = []
    for th in THRESHOLDS:
        vs = sorted({0, 1, 15, 16, 17, th - 1, max(0, th - 2), th // 2} & set(range(th)))
        for v in vs:
            leaked = (15 * v) // 16
            for u in (0, 1, 255):
                # exact equality, one below, one above, clamp boundaries
                for i in (th - leaked - u, th - leaked - u - 1, th - leaked - u + 1,
                          -leaked - u, -leaked - u - 1, -leaked - u + 1,
                          0, -(2 ** 31), 2 ** 31 - 1, -8192, 8128):
                    if -(2 ** 31) <= i < 2 ** 31:
                        out.append((th, v, i, u, *lif_update(v, i, u, th)))
        for _ in range(3000):
            v = rng.randrange(th)
            i = rng.choice((rng.randint(-300, 300), rng.randint(-(2 ** 31), 2 ** 31 - 1)))
            u = rng.randrange(256)
            out.append((th, v, i, u, *lif_update(v, i, u, th)))
    return out


def main():
    path = pathlib.Path(__file__).resolve().parent.parent / "tests" / "vectors" / "lif_cases.txt"
    c = cases()
    path.write_text(f"{len(c)}\n" + "\n".join(" ".join(map(str, x)) for x in c) + "\n")
    print(f"wrote {len(c)} LIF cases to {path}")


if __name__ == "__main__":
    main()
