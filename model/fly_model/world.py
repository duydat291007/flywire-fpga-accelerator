"""World, sensors, motor decoding, and the full closed-loop timestep (v2).

The fly has a position and one of 8 headings. Sensing is egocentric (left or
right of the heading), matching the left/right sensor neurons in the FlyWire
subcircuit. All arithmetic is small-integer so the RTL can match bit-exactly.

Order inside one timestep (identical in RTL):
  1. sensors from world state at step t          -> U[t]
  2. y = W s[t]                                   (reference.matvec)
  3. LIF for every neuron                         -> V[t+1], s[t+1]
  4. commit, step += 1
  5. world update from s[t+1]: accumulate motor counts; at the end of a
     MOVE_WINDOW apply one action; threat pursuit, catch, button respawns,
     LFSR advance

Assumptions that are NOT part of the FlyWire circuit (documented in
docs/flywire.md): the fly walks forward by default (walking rhythm generators
live in the ventral nerve cord, which FAFB does not contain); it turns at
random when the circuit gives no steering command; the threat is a simple
pursuer; sugar sensors are treated as short-range (contact-like) taste.
"""

from dataclasses import dataclass, field

from . import constants as C
from . import network as net
from .reference import matvec, lif_update

DX = (1, 1, 0, -1, -1, -1, 0, 1)
DY = (0, 1, 1, 1, 0, -1, -1, -1)
# heading index for sign(dx), sign(dy): HEAD_OF[sy + 1][sx + 1]
HEAD_OF = ((5, 6, 7), (4, 0, 0), (3, 2, 1))

# heading offsets tried, in order, for an escape jump blocked by walls
JUMP_OFFSETS = (0, 1, 7, 2, 6, 3, 5)

# motor counter slots
ESC, BACK, FWD, STL, STR, FEED = range(6)
N_MOTOR = 6


def lfsr_next(v):
    """16-bit Fibonacci LFSR, taps 16,14,13,11 (x^16 + x^14 + x^13 + x^11 + 1)."""
    bit = (v ^ (v >> 2) ^ (v >> 3) ^ (v >> 5)) & 1
    return (v >> 1) | (bit << 15)


def sgn(v):
    return (v > 0) - (v < 0)


def clamp(v):
    return max(0, min(C.ARENA - 1, v))


def side_of(heading, dx, dy):
    """-1 target on the left, +1 right, 0 straight ahead/behind (y grows downward)."""
    return sgn(DX[heading] * dy - DY[heading] * dx)


@dataclass
class World:
    fly: list = field(default_factory=lambda: list(C.FLY_START))
    heading: int = C.FLY_HEADING
    food: list = field(default_factory=lambda: list(C.FOOD_START))
    threat: list = field(default_factory=lambda: list(C.THREAT_START))
    food_present: bool = False
    threat_present: bool = False
    lfsr: int = C.LFSR_SEED
    eaten: int = 0
    caught: int = 0
    jumps: int = 0
    window_count: int = 0
    threat_phase: int = 0      # counts motor windows modulo THREAT_PERIOD
    motor_acc: list = field(default_factory=lambda: [0] * N_MOTOR)
    last_motor: list = field(default_factory=lambda: [0] * N_MOTOR)
    last_action: int = 0       # 0 walk, 1 back, 2 jump, 3 eat, 4 blocked
    pending_food_respawn: bool = False
    pending_threat_respawn: bool = False

    def rel(self, target):
        dx = target[0] - self.fly[0]
        dy = target[1] - self.fly[1]
        return dx, dy, max(abs(dx), abs(dy))

    def sensors(self):
        """External input vector U (N_NEURONS entries, 0..255)."""
        u = [0] * C.N_NEURONS
        if self.food_present:
            dx, dy, d = self.rel(self.food)
            if d <= C.TASTE_RADIUS:
                s = side_of(self.heading, dx, dy)
                for rng, active in ((net.FOOD_L, s <= 0), (net.FOOD_R, s >= 0)):
                    if active:
                        for n in rng:
                            u[n] = C.FOOD_DRIVE
        if self.threat_present:
            dx, dy, d = self.rel(self.threat)
            if d <= C.LOOM_RADIUS:
                drive = min(C.U_MAX, C.LOOM_BASE + C.LOOM_GAIN * (C.LOOM_RADIUS - d))
                s = side_of(self.heading, dx, dy)
                for rng, active in ((net.THREAT_L, s <= 0), (net.THREAT_R, s >= 0)):
                    if active:
                        for n in rng:
                            u[n] = drive
        return u

    def respawn_food(self):
        """After eating: a pseudo-random spot (the fly has to find it)."""
        self.food = [self.lfsr & 63, (self.lfsr >> 6) & 63]

    def place_food_ahead(self):
        """Food button: FOOD_AHEAD cells in front of the fly (clamped)."""
        self.food = [clamp(self.fly[0] + C.FOOD_AHEAD * DX[self.heading]),
                     clamp(self.fly[1] + C.FOOD_AHEAD * DY[self.heading])]

    def respawn_threat(self):
        """After a catch: the point diagonally opposite the fly (far away)."""
        self.threat = [(self.fly[0] + 32) & 63, (self.fly[1] + 32) & 63]

    def place_threat_side(self):
        """Threat button: THREAT_SIDE cells to the fly's left or right (LFSR bit 0)."""
        h = (self.heading + (2 if self.lfsr & 1 else 6)) & 7
        self.threat = [clamp(self.fly[0] + C.THREAT_SIDE * DX[h]),
                       clamp(self.fly[1] + C.THREAT_SIDE * DY[h])]

    def step_fly(self, heading, dist):
        """Move along heading; stop at walls. Returns True if fully blocked."""
        moved = False
        for _ in range(dist):
            nx, ny = self.fly[0] + DX[heading], self.fly[1] + DY[heading]
            if nx != clamp(nx) or ny != clamp(ny):
                break
            self.fly = [nx, ny]
            moved = True
        return not moved

    def act(self):
        m = self.motor_acc
        if m[ESC] >= C.ESCAPE_MIN:
            if self.threat_present:
                dx, dy, _ = self.rel(self.threat)
                if dx or dy:
                    self.heading = HEAD_OF[sgn(-dy) + 1][sgn(-dx) + 1]
            # jump away; if a wall blocks, try neighbouring headings, widening
            # to +-135 degrees so a cornered fly escapes along a wall. Only the
            # heading straight back toward the threat (+180) is never tried.
            for off in JUMP_OFFSETS:
                h = (self.heading + off) & 7
                if not self.step_fly(h, C.JUMP_DIST):
                    self.heading = h
                    break
            self.jumps = (self.jumps + 1) & 0xFFFF
            return 2
        if m[FEED] >= C.FEED_MIN and self.food_present and self.rel(self.food)[2] <= C.TASTE_RADIUS:
            self.eaten = (self.eaten + 1) & 0xFFFF
            self.respawn_food()
            return 3
        steer = m[STR] - m[STL]
        if steer >= C.TURN_MARGIN:
            self.heading = (self.heading + 1) & 7
        elif steer <= -C.TURN_MARGIN:
            self.heading = (self.heading - 1) & 7
        elif (self.lfsr & 7) == 0:                       # spontaneous turn
            self.heading = (self.heading + (1 if self.lfsr & 8 else -1)) & 7
        if m[BACK] - m[FWD] >= C.BACK_MARGIN:
            blocked = self.step_fly((self.heading + 4) & 7, 1)
            action = 1
        else:
            blocked = self.step_fly(self.heading, 1)
            action = 0
        if blocked:
            self.heading = (self.heading + 4) & 7        # turn around at a wall
            return 4
        return action

    def update(self, spikes):
        acc = self.motor_acc
        acc[ESC] += sum(spikes[n] for n in net.GIANT_FIBER)
        acc[BACK] += sum(spikes[n] for n in net.MDN)
        acc[FWD] += sum(spikes[n] for n in net.DNP09)
        acc[STL] += sum(spikes[n] for n in net.STEER_L)
        acc[STR] += sum(spikes[n] for n in net.STEER_R)
        acc[FEED] += sum(spikes[n] for n in net.FEED)
        self.window_count += 1
        if self.window_count == C.MOVE_WINDOW:
            self.last_action = self.act()
            self.last_motor = list(acc)
            self.motor_acc = [0] * N_MOTOR
            self.window_count = 0
            self.threat_phase = 0 if self.threat_phase == C.THREAT_PERIOD - 1 else self.threat_phase + 1
            if self.threat_present and self.threat_phase == 0:
                dx, dy, _ = self.rel(self.threat)
                self.threat = [self.threat[0] - sgn(dx), self.threat[1] - sgn(dy)]

        if self.threat_present and self.rel(self.threat)[2] <= 1:
            self.caught = (self.caught + 1) & 0xFFFF
            self.respawn_threat()
        if self.pending_food_respawn:          # food button
            self.place_food_ahead()
            self.pending_food_respawn = False
        if self.pending_threat_respawn:        # threat button
            self.place_threat_side()
            self.pending_threat_respawn = False
        self.lfsr = lfsr_next(self.lfsr)


class FlySim:
    """Closed-loop reference simulation of the FlyWire-driven fly."""

    def __init__(self, weights=None, threshold=net.THRESHOLD):
        self.W = weights if weights is not None else net.build_weights()
        self.threshold = threshold
        self.V = [0] * C.N_NEURONS
        self.s = [0] * C.N_NEURONS
        self.step_count = 0
        self.world = World()

    def step(self):
        u = self.world.sensors()
        y = matvec(self.W, self.s, C.N_NEURONS)
        nxt = [lif_update(self.V[i], y[i], u[i], self.threshold) for i in range(C.N_NEURONS)]
        self.V = [v for v, _ in nxt]
        self.s = [sp for _, sp in nxt]
        self.step_count += 1
        self.world.update(self.s)
        return u, y

    def state_tuple(self):
        w = self.world
        return (self.step_count, tuple(self.V), tuple(self.s), tuple(w.fly), w.heading,
                tuple(w.food), tuple(w.threat), w.eaten, w.caught, w.jumps, w.lfsr,
                w.window_count, w.threat_phase, tuple(w.motor_acc), tuple(w.last_motor),
                w.last_action)
