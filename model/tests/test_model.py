"""Unit tests for the Python reference model (stdlib unittest; no pytest needed).

Run: python -m unittest discover -s model/tests -v
"""

import pathlib
import random
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from fly_model import constants as C                       # noqa: E402
from fly_model import network as net                       # noqa: E402
from fly_model.packet import (PacketParser, crc16_ccitt_false, encode,  # noqa: E402
                              PACKET_LEN)
from fly_model.reference import lif_update, matvec         # noqa: E402
from fly_model.world import FlySim, World, lfsr_next, side_of, ESC, FEED  # noqa: E402


class TestReference(unittest.TestCase):
    def test_small_example(self):
        W = [[2, -1], [3, 4]]
        self.assertEqual(matvec(W, [5, 2], 2), [8, 23])

    def test_range_bound(self):
        """Extreme operands reach exactly the proved bounds and fit 32 bits."""
        n = C.N_NEURONS
        self.assertEqual(matvec([[-128] * n] * n, [-128] * n, n)[0], n * 16384)
        self.assertEqual(matvec([[127] * n] * n, [-128] * n, n)[0], -n * 16256)
        self.assertLess(n * 16384, 2 ** 23)        # 8 + 8 + log2(256) = 24-bit signed suffices

    def test_dim_ignores_outside(self):
        rng = random.Random(1)
        W = [[rng.randint(-128, 127) for _ in range(8)] for _ in range(8)]
        x = [rng.randint(-128, 127) for _ in range(8)]
        y3 = matvec(W, x, 3)
        W2 = [row[:] for row in W]
        for i in range(8):
            for j in range(8):
                if i >= 3 or j >= 3:
                    W2[i][j] = 0
        self.assertEqual(y3, matvec(W2, x, 8)[:3])

    def test_illegal(self):
        with self.assertRaises(ValueError):
            matvec([[1]], [1], 0)
        with self.assertRaises(ValueError):
            matvec([[200]], [1], 1)


class TestLif(unittest.TestCase):
    def test_threshold_equality_fires(self):
        # leaked = floor(15*16/16) = 15; 15 + 80 + 5 = 100 = threshold
        self.assertEqual(lif_update(16, 80, 5, 100), (0, 1))
        self.assertEqual(lif_update(16, 80, 4, 100), (99, 0))

    def test_leak_floor(self):
        self.assertEqual(lif_update(1, 0, 0, 100), (0, 0))      # floor(15/16) = 0
        self.assertEqual(lif_update(17, 0, 0, 100), (15, 0))    # floor(255/16) = 15
        self.assertEqual(lif_update(99, 0, 0, 100), (92, 0))

    def test_inhibition_clamps_to_zero(self):
        self.assertEqual(lif_update(50, -120, 0, 100), (0, 0))
        self.assertEqual(lif_update(50, -46, 0, 100), (0, 0))   # 46 - 46 = 0
        self.assertEqual(lif_update(50, -45, 0, 100), (1, 0))

    def test_invariant_checked(self):
        with self.assertRaises(ValueError):
            lif_update(100, 0, 0, 100)


class TestPacket(unittest.TestCase):
    def fields(self, rng):
        return dict(seq=rng.randrange(65536), step=rng.randrange(2 ** 32), flags=rng.randrange(32),
                    dropped_total=rng.randrange(65536), cycles=rng.randrange(2 ** 32),
                    fly=(rng.randrange(64), rng.randrange(64)),
                    food=(rng.randrange(64), rng.randrange(64)),
                    threat=(rng.randrange(64), rng.randrange(64)),
                    heading=rng.randrange(8), action=rng.randrange(5),
                    eaten=rng.randrange(65536), caught=rng.randrange(65536),
                    jumps=rng.randrange(65536),
                    motor=tuple(rng.randrange(33) for _ in range(6)),
                    activity=[rng.randrange(4) for _ in range(256)],
                    probe_base=8 * rng.randrange(32),
                    potentials=[rng.randrange(65536) for _ in range(8)])

    def test_crc_check_value(self):
        self.assertEqual(crc16_ccitt_false(b"123456789"), 0x29B1)

    def test_roundtrip(self):
        rng = random.Random(2)
        for _ in range(200):
            f = self.fields(rng)
            pkt = encode(f)
            self.assertEqual(len(pkt), PACKET_LEN)
            out = PacketParser().feed(pkt)
            self.assertEqual(len(out), 1)
            for k, v in f.items():
                got = out[0][k]
                self.assertEqual(tuple(got) if isinstance(v, tuple) else got, v, k)

    def test_byte_order(self):
        f = self.fields(random.Random(3))
        f.update(seq=0x1234, step=0xA1B2C3D4, heading=5, action=2)
        pkt = encode(f)
        self.assertEqual(pkt[4:6], b"\x34\x12")
        self.assertEqual(pkt[6:10], b"\xD4\xC3\xB2\xA1")
        self.assertEqual(pkt[23], 0x25)

    def test_partial_reads_and_garbage(self):
        rng = random.Random(4)
        pkts = [encode(dict(self.fields(rng), seq=i)) for i in range(50)]
        stream = b"\x00\xA5\x13" + b"".join(pkts)
        p = PacketParser()
        out = []
        i = 0
        while i < len(stream):              # random chunk sizes, including 1 byte
            n = rng.randint(1, 40)
            out += p.feed(stream[i:i + n])
            i += n
        self.assertEqual([o["seq"] for o in out], list(range(50)))
        self.assertEqual(p.crc_errors, 0)
        self.assertEqual(p.seq_gaps, 0)

    def test_corruption_resync(self):
        rng = random.Random(5)
        pkts = [bytearray(encode(dict(self.fields(rng), seq=i))) for i in range(30)]
        pkts[10][40] ^= 0x01                 # corrupt one payload bit
        pkts[20] = pkts[20][:30]             # truncate one packet
        p = PacketParser()
        out = p.feed(b"".join(pkts))
        seqs = [o["seq"] for o in out]
        self.assertNotIn(10, seqs)
        self.assertNotIn(20, seqs)
        self.assertEqual(len(seqs), 28)
        self.assertGreaterEqual(p.crc_errors, 2)
        self.assertEqual(p.seq_gaps, 2)

    def test_false_sync_in_payload(self):
        f = self.fields(random.Random(6))
        # activity bytes 0xA5, 0x5A inside the payload (2-bit fields, LSB first)
        f["activity"] = [1, 1, 2, 2, 2, 2, 1, 1] * 32
        pkts = encode(dict(f, seq=1)) + encode(dict(f, seq=2))
        self.assertIn(b"\xA5\x5A", pkts[36:100])
        out = PacketParser().feed(b"\xA5\x5A" + pkts)  # a stray sync before real data
        self.assertEqual([o["seq"] for o in out], [1, 2])


class TestWorld(unittest.TestCase):
    def test_lfsr_period(self):
        v, seen = C.LFSR_SEED, 0
        while True:
            v = lfsr_next(v)
            seen += 1
            if v == C.LFSR_SEED:
                break
        self.assertEqual(seen, 65535)      # maximal-length taps

    def test_side_of(self):
        # heading 0 faces +x; y grows downward, so +y is to the fly's right
        self.assertEqual(side_of(0, 5, 3), 1)
        self.assertEqual(side_of(0, 5, -3), -1)
        self.assertEqual(side_of(0, 5, 0), 0)
        self.assertEqual(side_of(2, 4, 4), -1)      # facing +y, +x is on the left
        self.assertEqual(side_of(6, 4, -4), 1)

    def test_sensors_egocentric(self):
        w = World()
        w.food_present = True
        w.food = [w.fly[0] + 2, w.fly[1] - 2]       # ahead-left, within taste range
        u = w.sensors()
        self.assertTrue(all(u[n] == C.FOOD_DRIVE for n in net.FOOD_L))
        self.assertTrue(all(u[n] == 0 for n in net.FOOD_R))
        w.food = [w.fly[0] + 3, w.fly[1]]           # straight ahead: both sides
        u = w.sensors()
        self.assertTrue(all(u[n] == C.FOOD_DRIVE for n in list(net.FOOD_L) + list(net.FOOD_R)))
        w.food = [w.fly[0] + C.TASTE_RADIUS + 1, w.fly[1]]
        self.assertEqual(sum(w.sensors()), 0)       # out of taste range
        w.food_present = False
        w.threat_present = True
        w.threat = [w.fly[0], w.fly[1] + 4]         # right side, distance 4
        u = w.sensors()
        drive = C.LOOM_BASE + C.LOOM_GAIN * (C.LOOM_RADIUS - 4)
        self.assertTrue(all(u[n] == drive for n in net.THREAT_R))
        self.assertTrue(all(u[n] == 0 for n in net.THREAT_L))
        self.assertTrue(all(v == 0 for v in u[32:]))

    def test_button_placements(self):
        w = World()
        w.heading = 0
        w.place_food_ahead()
        self.assertEqual(w.food, [w.fly[0] + C.FOOD_AHEAD, w.fly[1]])
        w.fly = [62, 10]
        w.place_food_ahead()
        self.assertEqual(w.food, [63, 10])          # clamped at the wall
        w.fly, w.lfsr = [30, 30], 1                 # lfsr bit 0 -> right side (heading + 2)
        w.place_threat_side()
        self.assertEqual(w.threat, [30, 30 + C.THREAT_SIDE])

    def test_jump_away_and_wall_retry(self):
        w = World()
        w.threat_present = True
        w.fly, w.threat = [20, 20], [25, 20]        # threat to the east
        w.motor_acc[ESC] = 1
        self.assertEqual(w.act(), 2)
        self.assertEqual(w.fly, [20 - C.JUMP_DIST, 20])
        w.fly, w.threat = [0, 20], [3, 20]          # wall directly behind: try neighbours
        w.motor_acc[ESC] = 1
        w.act()
        self.assertNotEqual(w.fly, [0, 20])

    def test_cornered_fly_escapes_along_wall(self):
        w = World()
        w.threat_present = True
        w.fly, w.threat = [0, 0], [3, 3]            # trapped in a corner, threat diagonal
        w.motor_acc[ESC] = 1
        self.assertEqual(w.act(), 2)
        self.assertNotEqual(w.fly, [0, 0])          # +-135 degree tries slide along a wall
        self.assertTrue(w.fly[0] == 0 or w.fly[1] == 0)

    def test_eating_needs_proboscis_spikes(self):
        w = World()
        w.food_present = True
        w.food = [w.fly[0] + 1, w.fly[1]]
        self.assertNotEqual(w.act(), 3)             # no feeding spikes: no meal
        w.food = [w.fly[0] + 1, w.fly[1]]
        w.motor_acc = [0] * 6
        w.motor_acc[FEED] = C.FEED_MIN
        self.assertEqual(w.act(), 3)
        self.assertEqual(w.eaten, 1)


class TestNetwork(unittest.TestCase):
    """The FlyWire subcircuit, driven with fixed stimuli (no world feedback)."""

    @classmethod
    def setUpClass(cls):
        cls.W = net.build_weights()

    def run_net(self, drive_ranges, steps, level=60):
        V = [0] * C.N_NEURONS
        s = [0] * C.N_NEURONS
        hist = []
        u = [0] * C.N_NEURONS
        for rng_ in drive_ranges:
            for n in rng_:
                u[n] = level
        for _ in range(steps):
            y = matvec(self.W, s, C.N_NEURONS)
            nxt = [lif_update(V[i], y[i], u[i], net.THRESHOLD) for i in range(C.N_NEURONS)]
            V = [v for v, _ in nxt]
            s = [b for _, b in nxt]
            hist.append(s)
        return hist

    @staticmethod
    def count(hist, rng_):
        return sum(h[n] for h in hist for n in rng_)

    def test_weights_from_flywire(self):
        nz = [w for row in self.W for w in row if w]
        self.assertGreater(len(nz), 2000)
        self.assertTrue(all(-127 <= w <= 127 for w in nz))
        self.assertTrue(any(w < 0 for w in nz) and any(w > 0 for w in nz))
        neurons = net.load_neurons()
        self.assertEqual([neurons[i]["primary_type"] for i in net.GIANT_FIBER], ["DNp01", "DNp01"])
        self.assertTrue(all("proboscis" in neurons[i]["role"] for i in net.FEED))

    def test_quiet_without_stimulus(self):
        hist = self.run_net([], 50)
        self.assertEqual(sum(map(sum, hist)), 0)

    def test_looming_drives_giant_fiber(self):
        for side in (net.THREAT_L, net.THREAT_R):
            hist = self.run_net([side], 40)
            self.assertGreater(self.count(hist, net.GIANT_FIBER), 0)

    def test_sugar_drives_proboscis(self):
        hist = self.run_net([net.FOOD_L, net.FOOD_R], 40)
        self.assertGreater(self.count(hist, net.FEED), 0)
        self.assertEqual(self.count(hist, net.GIANT_FIBER), 0)   # sugar alone never triggers escape

    def test_lesion_removes_behavior(self):
        W0 = [[0] * C.N_NEURONS for _ in range(C.N_NEURONS)]
        saved, self.W = self.W, W0
        try:
            hist = self.run_net([net.THREAT_L, net.FOOD_L], 40)
        finally:
            self.W = saved
        self.assertEqual(self.count(hist, net.GIANT_FIBER) + self.count(hist, net.FEED), 0)


class TestClosedLoop(unittest.TestCase):
    def test_food_button_leads_to_meal(self):
        sim = FlySim()
        sim.world.food_present = True
        sim.world.pending_food_respawn = True
        for _ in range(80):
            sim.step()
        self.assertGreaterEqual(sim.world.eaten, 1)

    def test_threat_button_leads_to_jump(self):
        sim = FlySim()
        sim.world.threat_present = True
        sim.world.pending_threat_respawn = True
        for _ in range(40):
            sim.step()
        self.assertGreaterEqual(sim.world.jumps, 1)


if __name__ == "__main__":
    unittest.main()
