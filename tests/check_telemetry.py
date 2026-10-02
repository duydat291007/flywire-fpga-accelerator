#!/usr/bin/env python3
"""Check a telemetry byte capture from tb_telemetry_e2e against the model.

usage: check_telemetry.py BYTES_FILE TRACE_FILE --probe G --cycles C --drops {none,some,any}

Checks, for every packet:
  - parser statistics: no CRC/header errors, no discarded bytes, no sequence gaps
  - step number exists in the trace; world fields, counters, and the last
    motor window equal the model state after that step
  - probe potentials equal the model's V for neurons 8G..8G+7
  - activity counts equal min(3, spikes since the previous packet's step),
    which must hold even across dropped snapshots
  - flags: running, food/threat presence of that step, systolic bit, and the
    dropped flag set exactly when dropped_total increased
  - cycles field equals the measured per-step latency (or 0 before step 1)
"""

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "model"))
from fly_model import constants as C                 # noqa: E402
from fly_model.packet import PacketParser             # noqa: E402


def load_trace(path):
    lines = pathlib.Path(path).read_text().split("\n")
    n = int(lines[0])
    N = C.N_NEURONS
    states = {0: dict(fly=C.FLY_START, food=C.FOOD_START, threat=C.THREAT_START,
                      heading=C.FLY_HEADING, action=0, eaten=0, caught=0, jumps=0,
                      motor=(0,) * 6, spikes=[0] * N, V=[0] * N, food_p=0, threat_p=0)}
    for s in range(1, n + 1):
        t = lines[s].split()
        f, th = int(t[0]), int(t[1])
        assert int(t[4]) == s
        v = list(map(int, t[5:23]))      # step .. m5 (t[5]..t[22])
        bits = int(t[23], 16)
        states[s] = dict(fly=(v[1], v[2]), heading=v[3], food=(v[4], v[5]), threat=(v[6], v[7]),
                         eaten=v[8], caught=v[9], jumps=v[10], action=v[11],
                         motor=tuple(v[12:18]), spikes=[(bits >> i) & 1 for i in range(N)],
                         V=list(map(int, t[24:24 + N])), food_p=f, threat_p=th)
    return states


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bytes_file")
    ap.add_argument("trace")
    ap.add_argument("--probe", type=int, required=True)
    ap.add_argument("--cycles", type=int, required=True)
    ap.add_argument("--drops", choices=("none", "some", "any"), default="any",
                    help="none: link has headroom; some: period forces drops")
    a = ap.parse_args()

    data = bytes(int(x, 16) for x in pathlib.Path(a.bytes_file).read_text().split())
    states = load_trace(a.trace)
    parser = PacketParser()
    pkts = parser.feed(data)
    errors = []

    def err(msg):
        errors.append(msg)
        if len(errors) < 10:
            print("FAIL:", msg)

    if parser.crc_errors or parser.header_errors or parser.discarded_bytes or parser.seq_gaps:
        err(f"parser stats crc={parser.crc_errors} hdr={parser.header_errors} "
            f"discarded={parser.discarded_bytes} gaps={parser.seq_gaps}")
    if not pkts:
        err("no packets")

    prev_step, prev_dropped = 0, 0
    for p in pkts:
        st = p["step"]
        if st not in states:
            err(f"seq {p['seq']}: step {st} beyond trace")
            continue
        m = states[st]
        for key in ("fly", "food", "threat", "motor"):
            if tuple(p[key]) != tuple(m[key]):
                err(f"seq {p['seq']} step {st}: {key} {p[key]} != model {m[key]}")
        for key in ("eaten", "caught", "jumps", "heading", "action"):
            if p[key] != m[key]:
                err(f"seq {p['seq']} step {st}: {key} {p[key]} != model {m[key]}")
        g = a.probe
        if p["probe_base"] != 8 * g or p["potentials"] != m["V"][8 * g:8 * g + 8]:
            err(f"seq {p['seq']} step {st}: potentials {p['potentials']} != {m['V'][8*g:8*g+8]}")
        expect_act = [min(3, sum(states[s]["spikes"][i] for s in range(prev_step + 1, st + 1)))
                      for i in range(C.N_NEURONS)]
        if p["activity"] != expect_act:
            err(f"seq {p['seq']} step {st}: activity mismatch (prev step {prev_step})")
        dropped_now = p["dropped_total"] > prev_dropped
        exp_flags = (1 | (m["food_p"] << 1) | (m["threat_p"] << 2) | (int(dropped_now) << 3) | 0x10)
        if st == 0:
            exp_flags &= ~0x06
        if p["flags"] != exp_flags:
            err(f"seq {p['seq']} step {st}: flags {p['flags']:#04x} != {exp_flags:#04x}")
        exp_cycles = a.cycles if st > 0 else 0
        if p["cycles"] != exp_cycles:
            err(f"seq {p['seq']} step {st}: cycles {p['cycles']} != {exp_cycles}")
        prev_step, prev_dropped = st, p["dropped_total"]

    total_drops = pkts[-1]["dropped_total"] if pkts else 0
    if a.drops == "some" and total_drops == 0:
        err("expected dropped snapshots but none were reported")
    if a.drops == "none" and total_drops != 0:
        err(f"unexpected drops: {total_drops}")

    if errors:
        print(f"FAIL check_telemetry: {len(errors)} errors in {len(pkts)} packets")
        sys.exit(1)
    print(f"PASS check_telemetry: {len(pkts)} packets, steps {pkts[0]['step']}..{pkts[-1]['step']}, "
          f"{total_drops} dropped snapshots, all fields match the model")


if __name__ == "__main__":
    main()
