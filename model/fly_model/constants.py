"""Numeric constants shared by every part of the reference model.

These values are the single source of truth. `export.py` writes them into
`rtl/common/fly_cfg_pkg.sv` so RTL and model cannot drift apart.
"""

N_NEURONS = 256         # neurons in the FlyWire subcircuit (= MVU N_MAX)
W_BITS = 8              # signed weights
X_BITS = 8              # signed generic inputs
ACC_BITS = 32           # signed accumulator/result
V_BITS = 16             # unsigned stored potential
U_BITS = 8              # unsigned external input

W_MIN, W_MAX = -(1 << (W_BITS - 1)), (1 << (W_BITS - 1)) - 1
X_MIN, X_MAX = -(1 << (X_BITS - 1)), (1 << (X_BITS - 1)) - 1
ACC_MIN, ACC_MAX = -(1 << (ACC_BITS - 1)), (1 << (ACC_BITS - 1)) - 1
V_MAX = (1 << V_BITS) - 1
U_MAX = (1 << U_BITS) - 1

# World parameters (v2: heading-based fly, see world.py)
ARENA = 64                  # coordinates 0..63, y grows downward
FLY_START = (32, 32)
FLY_HEADING = 0             # 0 = +x (east), steps of 45 degrees clockwise
FOOD_START = (8, 12)
THREAT_START = (56, 52)
LFSR_SEED = 0xACE1
TASTE_RADIUS = 3            # sugar sensors respond within this Chebyshev distance
FOOD_DRIVE = 60             # external input to each active sugar sensor
LOOM_RADIUS = 12            # looming detectors respond within this distance
LOOM_BASE = 40              # drive = LOOM_BASE + LOOM_GAIN * (LOOM_RADIUS - d)
LOOM_GAIN = 5
MOVE_WINDOW = 8             # timesteps per motor decision
ESCAPE_MIN = 1              # giant-fiber spikes per window that trigger a jump
JUMP_DIST = 6
FEED_MIN = 2                # proboscis motor spikes per window needed to eat
TURN_MARGIN = 2             # steering spike-count difference needed to turn
BACK_MARGIN = 2             # MDN minus DNp09 spikes needed to walk backward
THREAT_PERIOD = 3           # windows between threat moves toward the fly
FOOD_AHEAD = 5              # food button places food this far ahead of the fly
THREAT_SIDE = 8             # threat button places the threat this far to one side
