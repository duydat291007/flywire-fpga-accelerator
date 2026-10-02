#!/usr/bin/env python3
"""Pick a ~256-neuron FlyWire subcircuit (food -> approach, looming -> escape).

Input : FlyWire Codex FAFB v783 exports in data/flywire/ (see docs/flywire.md).
Output: model/flywire/out/circuit_neurons.csv  (index -> root_id, role, type, side)
        model/flywire/out/circuit_edges.csv    (pre_idx, post_idx, syn_count, sign)
        model/flywire/out/circuit_report.md    (selection summary, retained input)

Method (deterministic, no tuning of individual connections):
  1. Aggregate connections over neuropils per (pre, post); keep syn_count >= 5
     (the threshold used in the FlyWire papers).
  2. Sign from the presynaptic neuron's predicted transmitter:
     ACH -> +1, GABA/GLUT -> -1, DA/SER/OCT (modulatory) -> 0 (dropped).
  3. Fixed endpoints: sugar/water gustatory receptor neurons (food) and
     LPLC2/LC4 looming detectors (threat) as sensors; selected descending
     neurons as outputs.
  4. Sensors are ranked by their multi-hop backward reach from the outputs;
     the best few per side are kept.
  5. Intermediates come from strongest paths (edge cost = -log of the input
     fraction a connection supplies) from each sensor group/side to its target
     descending neurons. Pathways take turns; used edges are penalised so
     later paths find alternatives.

This is a heavily reduced subcircuit: every neuron loses inputs from outside
the selection. The report quantifies that loss.
"""

import argparse
import os
import sys

import numpy as np
import pandas as pd
import scipy.sparse as sp
from scipy.sparse import csgraph

N_TOTAL = 256
SYN_MIN = 5
MAX_HOPS = 4
PATH_PENALTY = 1.0   # added to an edge's cost each time a selected path uses it
FOOD_PER_SIDE = 8
THREAT_PER_SIDE = 8
FEED_MN_PER_SIDE = 2
OUTPUT_TYPES = {
    # type: role
    "DNp01": "escape (giant fiber)",
    "DNp02": "escape-related",
    "DNp04": "escape-related",
    "DNp06": "escape-related",
    "DNp11": "escape-related",
    "MDN": "backward walking",
    "DNp09": "forward walking / approach",
    "DNa01": "steering",
    "DNa02": "steering",
}
SIGN = {"ACH": 1, "GABA": -1, "GLUT": -1}


def load(data_dir):
    rd = lambda f: pd.read_csv(os.path.join(data_dir, f), dtype={"root_id": "int64"})
    cls = rd("classification.csv.gz")
    types = rd("consolidated_cell_types.csv.gz")
    neu = rd("neurons.csv.gz")
    names = rd("names.csv.gz")
    con = pd.read_csv(os.path.join(data_dir, "connections_princeton.csv.gz"),
                      usecols=["pre_root_id", "post_root_id", "syn_count"])
    meta = (cls.merge(types[["root_id", "primary_type"]], on="root_id", how="left")
               .merge(neu[["root_id", "nt_type"]], on="root_id", how="left")
               .merge(names[["root_id", "name"]], on="root_id", how="left"))
    return meta, con


def build_graph(meta, con):
    agg = con.groupby(["pre_root_id", "post_root_id"], as_index=False)["syn_count"].sum()
    agg = agg[agg.syn_count >= SYN_MIN]
    ids = meta.root_id.to_numpy()
    idx = pd.Series(np.arange(len(ids)), index=ids)
    agg = agg[agg.pre_root_id.isin(idx.index) & agg.post_root_id.isin(idx.index)]
    pre = idx[agg.pre_root_id].to_numpy()
    post = idx[agg.post_root_id].to_numpy()
    n = len(ids)
    A = sp.csr_matrix((agg.syn_count.to_numpy().astype(float), (pre, post)), shape=(n, n))
    return A, idx


def reach(M, seed, hops):
    """Sum over 1..hops of seed propagated through row-stochastic-ish M."""
    v = seed.copy()
    total = np.zeros_like(seed)
    for _ in range(hops):
        v = M.T @ v
        total += v
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="data/flywire")
    ap.add_argument("--out", default="model/flywire/out")
    ap.add_argument("--n", type=int, default=N_TOTAL)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    meta, con = load(args.data)
    A, idx = build_graph(meta, con)
    n = A.shape[0]
    meta = meta.reset_index(drop=True)
    sign = meta.nt_type.map(SIGN).fillna(0).to_numpy()

    in_tot = np.asarray(A.sum(axis=0)).ravel()
    out_tot = np.asarray(A.sum(axis=1)).ravel()
    # forward: fraction of post's input from pre; backward: fraction of pre's output to post
    Ff = sp.diags(np.ones(n)) @ A @ sp.diags(1.0 / np.maximum(in_tot, 1))
    Fb = (sp.diags(1.0 / np.maximum(out_tot, 1)) @ A).T.tocsr()

    is_food = (meta["class"] == "gustatory") & (meta.sub_class == "sugar/water")
    is_threat = meta.primary_type.isin(["LPLC2", "LC4"])
    is_out = meta.primary_type.isin(OUTPUT_TYPES.keys())

    out_seed = is_out.to_numpy().astype(float)
    back = reach(Fb, out_seed, MAX_HOPS)
    fwd_food = reach(Ff, is_food.to_numpy().astype(float), MAX_HOPS)
    fwd_thr = reach(Ff, is_threat.to_numpy().astype(float), MAX_HOPS)

    def pick_sensors(mask, per_side):
        cand = meta[mask].assign(score=back[mask.to_numpy()])
        chosen = []
        for side in ("left", "right"):
            chosen += cand[cand.side == side].nlargest(per_side, "score").index.tolist()
        return chosen

    food = pick_sensors(is_food, FOOD_PER_SIDE)
    threat = pick_sensors(is_threat, THREAT_PER_SIDE)
    # Feeding outputs: proboscis motor neurons with the strongest multi-hop
    # forward reach from the selected sugar sensors, FEED_MN_PER_SIDE per side.
    seed = np.zeros(n)
    seed[food] = 1.0
    fwd = reach(Ff, seed, MAX_HOPS)
    is_pmn = meta.sub_class == "proboscis_motor_neuron"
    pmn = []
    for side in ("left", "right"):
        cand = meta[is_pmn & (meta.side == side)].assign(score=fwd[(is_pmn & (meta.side == side)).to_numpy()])
        pmn += cand.nlargest(FEED_MN_PER_SIDE, "score").index.tolist()
    outs = meta[is_out].index.tolist() + pmn
    # Fixed output order so hardware can address groups as contiguous ranges:
    # giant fiber, other escape DNs, MDN, DNp09, steering left, steering right,
    # proboscis motor neurons. Within a group: left before right.
    rank = {"DNp01": 0, "DNp02": 1, "DNp04": 1, "DNp06": 1, "DNp11": 1, "MDN": 2,
            "DNp09": 3, "DNa01": 4, "DNa02": 4}
    def okey(g):
        t = meta.primary_type[g]
        r = rank.get(t, 6)
        if r == 4 and meta.side[g] == "right":
            r = 5
        return (r, 0 if meta.side[g] == "left" else 1, str(t), meta.root_id[g])
    outs = sorted(outs, key=okey)
    fixed = set(food) | set(threat) | set(outs)
    n_inter = args.n - len(fixed)
    if n_inter < 0:
        sys.exit("budget smaller than fixed endpoints")

    # Path-based selection. Edge cost = -log(fraction of the postsynaptic
    # neuron's input that this connection supplies), so the cheapest path is
    # the chain with the strongest relative drive. Only fast-transmitter edges
    # (ACh/GABA/Glu) are used. Four pathways (food/threat x left/right) take
    # turns adding their next-best path to their next target neuron; edges
    # already used are penalised so later paths explore alternatives.
    fast = sign != 0
    Ac = A.tocoo()
    keep = fast[Ac.row]
    frac = Ac.data[keep] / np.maximum(in_tot[Ac.col[keep]], 1)
    G = sp.csr_matrix((-np.log(frac) + 1e-3, (Ac.row[keep], Ac.col[keep])), shape=(n, n))
    G.sort_indices()

    def edge_pos(u, v):
        lo, hi = G.indptr[u], G.indptr[u + 1]
        return lo + np.searchsorted(G.indices[lo:hi], v)

    steer = meta.index[meta.primary_type.isin(["DNa01", "DNa02"])].tolist()
    food_targets = pmn + steer
    thr_targets = meta.index[meta.primary_type.isin(["DNp01", "DNp02", "DNp04", "DNp06",
                                                      "DNp11", "MDN"])].tolist() + steer
    paths = []
    for label, group, targets in (("food", food, food_targets), ("threat", threat, thr_targets)):
        for side in ("left", "right"):
            members = [g for g in group if meta.side[g] == side]
            paths.append({"label": f"{label} path {side}", "src": members,
                          "targets": targets, "t": 0})
    inter, taken = [], set(fixed)
    stall = 0
    while len(inter) < n_inter and stall < 200:
        for p in paths:
            if len(inter) >= n_inter:
                break
            dist, pred, _ = csgraph.dijkstra(G, indices=p["src"], min_only=True,
                                          return_predecessors=True)
            tgt = p["targets"][p["t"] % len(p["targets"])]
            p["t"] += 1
            if not np.isfinite(dist[tgt]):
                stall += 1
                continue
            node, chain = tgt, []
            while pred[node] >= 0:
                chain.append((pred[node], node))
                node = pred[node]
            added = 0
            for u, v in reversed(chain):
                G.data[edge_pos(u, v)] += PATH_PENALTY
                if v not in taken and len(inter) < n_inter:
                    inter.append((v, p["label"]))
                    taken.add(v)
                    added += 1
            stall = 0 if added else stall + 1

    rows = ([(g, "sensor: food (sugar GRN)") for g in food] +
            [(g, "sensor: threat (looming)") for g in threat] +
            [(g, f"intermediate ({r})") for g, r in inter] +
            [(g, "output: " + OUTPUT_TYPES.get(meta.primary_type[g], "feeding (proboscis motor)"))
             for g in outs])
    sel = np.array([g for g, _ in rows])
    tab = meta.loc[sel, ["root_id", "super_class", "class", "primary_type", "side",
                          "nt_type", "name"]].reset_index(drop=True)
    tab.insert(0, "index", np.arange(len(sel)))
    tab.insert(2, "role", [r for _, r in rows])
    tab.to_csv(os.path.join(args.out, "circuit_neurons.csv"), index=False)

    sub = A[sel][:, sel].tocoo()
    edges = pd.DataFrame({"pre_idx": sub.row, "post_idx": sub.col,
                          "syn_count": sub.data.astype(int),
                          "sign": sign[sel][sub.row].astype(int)})
    edges.to_csv(os.path.join(args.out, "circuit_edges.csv"), index=False)

    kept_in = np.asarray(A[sel][:, sel].sum(axis=0)).ravel()
    frac = kept_in / np.maximum(in_tot[sel], 1)
    signed = edges[edges.sign != 0]

    # reachability check: can each output be reached from each sensor group inside the circuit?
    S = sp.csr_matrix((np.ones(len(signed)), (signed.pre_idx, signed.post_idx)),
                      shape=(len(sel), len(sel)))
    def reachable(src):
        v = np.zeros(len(sel)); v[src] = 1
        seen = v.copy()
        for _ in range(12):
            v = (S.T @ v > 0).astype(float)
            seen = np.maximum(seen, v)
        return seen
    rf = reachable(np.arange(len(food)))
    rt = reachable(np.arange(len(food), len(food) + len(threat)))
    out_idx = tab.index[tab.role.str.startswith("output")]

    with open(os.path.join(args.out, "circuit_report.md"), "w") as f:
        f.write("# FlyWire subcircuit selection\n\n")
        f.write(f"Source: FlyWire Codex FAFB v783 export, {n} neurons, "
                f"{A.nnz} connections with >= {SYN_MIN} synapses.\n\n")
        f.write(f"Selected {len(sel)} neurons, {len(edges)} internal connections "
                f"({len(signed)} with a fast transmitter sign; "
                f"{(edges.sign == 1).sum()} excitatory, {(edges.sign == -1).sum()} inhibitory).\n\n")
        f.write("| role | count |\n|---|---|\n")
        for r, c in tab.role.value_counts().items():
            f.write(f"| {r} | {c} |\n")
        f.write("\n## Input retained inside the subcircuit\n\n")
        f.write("Fraction of each neuron's input synapses that come from other selected neurons.\n\n")
        f.write("| group | median | min | max |\n|---|---|---|---|\n")
        for label, m in (("intermediate", tab.role.str.startswith("inter")),
                         ("output", tab.role.str.startswith("output"))):
            v = frac[m.to_numpy()]
            f.write(f"| {label} | {np.median(v):.2f} | {v.min():.2f} | {v.max():.2f} |\n")
        f.write("\n## Outputs\n\n| idx | type | side | inputs kept | reachable from food | from threat |\n|---|---|---|---|---|---|\n")
        for k in out_idx:
            f.write(f"| {k} | {tab.primary_type[k]} | {tab.side[k]} | {frac[k]:.2f} | "
                    f"{'yes' if rf[k] else 'no'} | {'yes' if rt[k] else 'no'} |\n")
        f.write("\n## Intermediate cell types (top 30 by count)\n\n")
        it = tab[tab.role.str.startswith("inter")]
        for (t, r), c in it.groupby(["primary_type", "role"]).size().sort_values(ascending=False).head(30).items():
            f.write(f"- {t} ({r}): {c}\n")
    print(open(os.path.join(args.out, "circuit_report.md")).read())


if __name__ == "__main__":
    main()
