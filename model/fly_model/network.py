"""FlyWire-derived 256-neuron network (v2).

The neuron list and connections come from model/flywire/select_circuit.py,
run on the FlyWire Codex FAFB v783 export. Index layout (fixed by that script):

    0-7    food sensors, left      (sugar/water gustatory receptor neurons)
    8-15   food sensors, right
    16-23  threat sensors, left    (LPLC2 / LC4 looming detectors)
    24-31  threat sensors, right
    32-231 intermediate neurons    (strongest sensor -> output paths)
    232-233 giant fiber DNp01 L, R          (escape)
    234-241 DNp02/04/06/11 L then R         (escape-related)
    242-245 MDN L, L, R, R                  (backward walking)
    246-247 DNp09 L, R                      (forward walking)
    248-249 DNa01, DNa02 left               (steering)
    250-251 DNa01, DNa02 right              (steering)
    252-255 proboscis motor neurons L, L, R, R (feeding)

Weight rule (the only conversion applied; no per-connection tuning):
    W[post][pre] = sign(pre transmitter) * min(127, SCALE * synapse_count)
with ACh -> +1, GABA/Glu -> -1, modulatory transmitters dropped.
"""

import csv
import os

from .constants import N_NEURONS

THRESHOLD = 100
SCALE = 2                       # global gain compensating for removed inputs
W_CLIP = 127

FOOD_L, FOOD_R = range(0, 8), range(8, 16)
THREAT_L, THREAT_R = range(16, 24), range(24, 32)
INTER = range(32, 232)
GIANT_FIBER = range(232, 234)
ESCAPE_OTHER = range(234, 242)
MDN = range(242, 246)
DNP09 = range(246, 248)
STEER_L = range(248, 250)
STEER_R = range(250, 252)
FEED = range(252, 256)

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "flywire", "out")


def load_neurons(data_dir=DATA_DIR):
    with open(os.path.join(data_dir, "circuit_neurons.csv"), newline="") as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == N_NEURONS, f"expected {N_NEURONS} neurons, found {len(rows)}"
    return rows


def build_weights(data_dir=DATA_DIR, scale=SCALE):
    """Return W[destination][source] as a list of lists of ints in [-127, 127]."""
    W = [[0] * N_NEURONS for _ in range(N_NEURONS)]
    with open(os.path.join(data_dir, "circuit_edges.csv"), newline="") as f:
        for r in csv.DictReader(f):
            sign = int(r["sign"])
            if sign:
                W[int(r["post_idx"])][int(r["pre_idx"])] = sign * min(W_CLIP, scale * int(r["syn_count"]))
    return W


_NEURONS = None


def role_of(n):
    global _NEURONS
    if _NEURONS is None:
        _NEURONS = load_neurons()
    r = _NEURONS[n]
    return f"{r['primary_type']} {r['side'][:1].upper()} - {r['role']}"
