#!/usr/bin/env python3
"""Generate MVU test vectors from the mathematical reference model.

Output: tests/vectors/mvu_cases.txt (whitespace-separated decimal integers)

    <num_cases>
    per case:
      <case_id> <dim> <reuse> <xmode> <stall_pct> <gap_pct> <rst_at> <rst_after_k>
      N_MAX*N_MAX weights, row-major W[dst][src]  (only if reuse == 0)
      N_MAX inputs x[j]                             (only if reuse == 0)
      <n_expected> expected results y[0..n-1]

    reuse=1       : keep the previous case's memory contents (back-to-back test)
    xmode=1       : load x through the binary bulk port (x in {0,1})
    rst_at>=0     : assert reset this many cycles after command acceptance
    rst_after_k>=0: assert reset after k results have been accepted (drain phase)
    After a reset the testbench reissues the same command and checks it.
    Illegal dims (0 or N_MAX+1) expect zero results and err_dim.

Entries outside dim are random garbage on purpose: they must never matter.
"""

import argparse
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from fly_model.reference import matvec          # noqa: E402

N_MAX = 64


def rand_matrix(rng, lo=-128, hi=127):
    return [[rng.randint(lo, hi) for _ in range(N_MAX)] for _ in range(N_MAX)]


def rand_vec(rng, lo=-128, hi=127):
    return [rng.randint(lo, hi) for _ in range(N_MAX)]


def fill(rng, dim, W_in, x_in):
    """Embed a dim x dim problem in garbage-filled N_MAX storage."""
    W = rand_matrix(rng)
    x = rand_vec(rng)
    for i in range(dim):
        for j in range(dim):
            W[i][j] = W_in[i][j]
        x[i] = x_in[i]
    return W, x


def build_cases(seed):
    rng = random.Random(seed)
    cases = []

    def add(name, dim, W=None, x=None, reuse=0, xmode=0, stall=0, gap=0, rst_at=-1, rst_k=-1):
        legal = 1 <= dim <= N_MAX
        exp = matvec(W, x, dim) if legal else []
        cases.append(dict(name=name, dim=dim, W=W, x=x, reuse=reuse, xmode=xmode,
                          stall=stall, gap=gap, rst_at=rst_at, rst_k=rst_k, exp=exp))

    def problem(dim, wgen, xgen):
        Wd = [[wgen(i, j) for j in range(dim)] for i in range(dim)]
        xd = [xgen(j) for j in range(dim)]
        return fill(rng, dim, Wd, xd)

    r8 = lambda *_: rng.randint(-128, 127)

    # --- directed -------------------------------------------------------
    add("zero_matrix", 64, *problem(64, lambda i, j: 0, r8))
    add("identity", 64, *problem(64, lambda i, j: 1 if i == j else 0, r8))
    for j in (0, 3, 4):
        add(f"onehot_x{j}", 5, *problem(5, r8, lambda k, j=j: 1 if k == j else 0))
    for (i0, j0) in ((0, 0), (2, 5), (6, 1), (6, 6)):
        add(f"isolated_w{i0}_{j0}", 7,
            *problem(7, lambda i, j, a=i0, b=j0: 77 if (i, j) == (a, b) else 0,
                     lambda k: 1 + k))
    add("extreme_max", 64, *problem(64, lambda i, j: -128, lambda j: -128))
    add("extreme_min", 64, *problem(64, lambda i, j: 127, lambda j: -128))
    add("extreme_mix", 64, *problem(64, lambda i, j: (-128, 127)[(i + j) % 2],
                                    lambda j: (-128, 127, -1, 1)[j % 4]))
    add("all_positive", 33, *problem(33, lambda *_: rng.randint(0, 127), lambda _: rng.randint(0, 127)))
    add("all_negative", 33, *problem(33, lambda *_: rng.randint(-128, -1), lambda _: rng.randint(-128, -1)))
    for d in (1, 2, 3, 4, 5, 7, 8, 9, 16, 17, 31, 33, 63, 64):
        add(f"dim{d}", d, *problem(d, r8, r8))

    # --- illegal dimensions ---------------------------------------------
    W, x = problem(4, r8, r8)
    add("illegal_dim0", 0, W, x)
    add("illegal_dim65", 65, W, x, reuse=1)

    # --- back-to-back with reused memory (stale-state checks) -----------
    W, x = problem(64, r8, r8)
    add("b2b_64", 64, W, x)
    for d in (5, 64, 1, 63, 64):
        add(f"b2b_reuse_{d}", d, W, x, reuse=1)

    # --- binary spike vectors through the bulk port ---------------------
    for d in (64, 13):
        W = rand_matrix(rng)
        x = [rng.randint(0, 1) for _ in range(N_MAX)]
        add(f"spikes_{d}", d, W, x, xmode=1)

    # --- backpressure and input gaps ------------------------------------
    for d, stall, gap in ((64, 50, 30), (5, 80, 0), (17, 90, 60), (1, 95, 10), (63, 30, 90)):
        add(f"stall{stall}_gap{gap}_dim{d}", d, *problem(d, r8, r8), stall=stall, gap=gap)

    # --- reset in different phases --------------------------------------
    W, x = problem(64, r8, r8)
    add("pre_reset_ref", 64, W, x)
    for at in (0, 1, 3, 20, 100, 400, 1000):
        add(f"reset_at_{at}", 64, W, x, reuse=1, rst_at=at)
    for k in (0, 1, 30, 63):
        add(f"reset_drain_k{k}", 64, W, x, reuse=1, rst_k=k, stall=40)
    W, x = problem(9, r8, r8)
    add("reset_partial_dim9", 9, W, x, rst_at=5)

    # --- constrained random ---------------------------------------------
    for n in range(30):
        d = rng.choice([rng.randint(1, 64), rng.choice((1, 3, 4, 5, 63, 64))])
        add(f"rand{n}_dim{d}", d, *problem(d, r8, r8),
            stall=rng.choice((0, 0, 25, 60)), gap=rng.choice((0, 20, 50)))
    return cases


def build_perf_cases(seed):
    """Identical benchmark workload for every configuration (no resets)."""
    rng = random.Random(seed)
    cases = []
    r8 = lambda *_: rng.randint(-128, 127)
    W = rand_matrix(rng)
    x = rand_vec(rng)
    first = True
    for d in (1, 2, 4, 5, 8, 16, 17, 32, 33, 48, 63, 64):
        cases.append(dict(name=f"perf_dim{d}", dim=d, W=W, x=x, reuse=0 if first else 1, xmode=0,
                          stall=0, gap=0, rst_at=-1, rst_k=-1, exp=matvec(W, x, d)))
        first = False
    for stall in (25, 50, 75, 90):
        cases.append(dict(name=f"perf_dim64_stall{stall}", dim=64, W=W, x=x, reuse=1, xmode=0,
                          stall=stall, gap=0, rst_at=-1, rst_k=-1, exp=matvec(W, x, 64)))
    return cases


def write(cases, path):
    with open(path, "w") as f:
        f.write(f"{len(cases)}\n")
        for cid, c in enumerate(cases):
            f.write(f"{cid} {c['dim']} {c['reuse']} {c['xmode']} {c['stall']} {c['gap']} "
                    f"{c['rst_at']} {c['rst_k']}\n")
            if not c["reuse"]:
                for row in c["W"]:
                    f.write(" ".join(map(str, row)) + "\n")
                f.write(" ".join(map(str, c["x"])) + "\n")
            f.write(f"{len(c['exp'])} " + " ".join(map(str, c["exp"])) + "\n")
    with open(path.with_suffix(".names"), "w") as f:
        for cid, c in enumerate(cases):
            f.write(f"{cid} {c['name']}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=20260930)
    ap.add_argument("--perf", action="store_true", help="write the benchmark workload instead")
    ap.add_argument("--out", default=str(pathlib.Path(__file__).resolve().parent.parent
                                         / "tests" / "vectors" / "mvu_cases.txt"))
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if args.perf and out.name == "mvu_cases.txt":
        out = out.with_name("mvu_perf.txt")
    cases = build_perf_cases(args.seed) if args.perf else build_cases(args.seed)
    write(cases, out)
    print(f"wrote {len(cases)} cases (seed {args.seed}) to {out}")


if __name__ == "__main__":
    main()
