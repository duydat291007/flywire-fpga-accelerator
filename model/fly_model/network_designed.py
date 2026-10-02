"""LEGACY (v1): deterministic, hand-designed 64-neuron network.

Superseded by the FlyWire subcircuit in network.py; kept for history and
for the 64-neuron regression configuration.

Roles (directions ordered L, R, U, D):
    0-3   food sensors          4-7   threat sensors
    8-11  food relay 1          16-19 threat relay 1
    12-15 food relay 2          20-23 threat relay 2
    32-35 food relay 3          36-39 threat relay 3
    24    alarm (any threat)    25-27 alarm delay chain
    28-31 lateral inhibitors (L->R, R->L, U->D, D->U)
    40-47 reserved, no synapses
    48-51 motor L  52-55 motor R  56-59 motor U  60-63 motor D

This is an engineered controller that happens to use spiking units. It makes
no claim about real fly circuitry.
"""

N_NEURONS = 64   # legacy v1 network size

THRESHOLD = 100

L, R, U, D = 0, 1, 2, 3
DIRS = "LRUD"
OPPOSITE = {L: R, R: L, U: D, D: U}

FOOD_SENSOR = 0
THREAT_SENSOR = 4
FOOD_RELAY = (8, 12, 32)
THREAT_RELAY = (16, 20, 36)
ALARM = 24
ALARM_CHAIN = (25, 26, 27)
LATERAL = 28            # 28: L pool -> inhibits R, 29: R -> L, 30: U -> D, 31: D -> U
RESERVED = range(40, 48)
MOTOR = 48              # pool d occupies MOTOR + 4*d .. +3

# Synaptic strengths
W_RELAY = 110           # one presynaptic spike is enough to fire the next stage
W_MOTOR = 60            # relay 3 -> each motor neuron of the pool
W_ALARM_IN = 110
W_CHAIN = 110
W_INHIBIT_FOOD = -120
W_LATERAL_IN = 30
W_LATERAL_OUT = -90


def motor_pool(direction):
    return range(MOTOR + 4 * direction, MOTOR + 4 * direction + 4)


def role_of(n):
    if n < 4:
        return f"food sensor {DIRS[n]}"
    if n < 8:
        return f"threat sensor {DIRS[n - 4]}"
    for layer, base in enumerate(FOOD_RELAY):
        if base <= n < base + 4:
            return f"food relay{layer + 1} {DIRS[n - base]}"
    for layer, base in enumerate(THREAT_RELAY):
        if base <= n < base + 4:
            return f"threat relay{layer + 1} {DIRS[n - base]}"
    if n == ALARM:
        return "alarm"
    if n in ALARM_CHAIN:
        return f"alarm chain {n - ALARM_CHAIN[0] + 1}"
    if LATERAL <= n < LATERAL + 4:
        return f"lateral inhibitor from {DIRS[n - LATERAL]}"
    if n in RESERVED:
        return "reserved"
    return f"motor {DIRS[(n - MOTOR) // 4]}{(n - MOTOR) % 4}"


def build_weights():
    """Return W[destination][source] as a list of lists of ints in [-128, 127]."""
    W = [[0] * N_NEURONS for _ in range(N_NEURONS)]

    def syn(src, dst, w):
        W[dst][src] = w

    for d in range(4):
        # Food pathway: sensor -> r1 -> r2 -> r3 -> motor pool (same direction)
        chain = [FOOD_SENSOR + d] + [base + d for base in FOOD_RELAY]
        for a, b in zip(chain, chain[1:]):
            syn(a, b, W_RELAY)
        for m in motor_pool(d):
            syn(chain[-1], m, W_MOTOR)

        # Threat pathway: sensor -> r1 -> r2 -> r3 -> motor pool (opposite direction)
        chain = [THREAT_SENSOR + d] + [base + d for base in THREAT_RELAY]
        for a, b in zip(chain, chain[1:]):
            syn(a, b, W_RELAY)
        for m in motor_pool(OPPOSITE[d]):
            syn(chain[-1], m, W_MOTOR)

        # Any threat-relay-1 activity triggers the alarm
        syn(THREAT_RELAY[0] + d, ALARM, W_ALARM_IN)

    # Alarm delay chain
    chain = [ALARM, *ALARM_CHAIN]
    for a, b in zip(chain, chain[1:]):
        syn(a, b, W_CHAIN)

    # Alarm and its chain inhibit food relays 2 and 3 (threat dominates food)
    for inh in chain:
        for d in range(4):
            syn(inh, FOOD_RELAY[1] + d, W_INHIBIT_FOOD)
            syn(inh, FOOD_RELAY[2] + d, W_INHIBIT_FOOD)

    # Lateral inhibition between opposing motor pools
    for d in range(4):
        inhibitor = LATERAL + d
        for m in motor_pool(d):
            syn(m, inhibitor, W_LATERAL_IN)
        for m in motor_pool(OPPOSITE[d]):
            syn(inhibitor, m, W_LATERAL_OUT)

    return W
