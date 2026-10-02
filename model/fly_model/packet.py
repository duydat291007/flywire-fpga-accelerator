"""Telemetry packet format v2, CRC, encoder, and a streaming parser.

Format (119 bytes, multi-byte fields little-endian) - see docs/specification.md 6.1.

    0-1   sync A5 5A           2  version (2)        3  payload length (113)
    4-5   seq                  6-9 step              10 flags
    11-12 dropped_total        13-16 cycles per neural update
    17-22 fly x,y  food x,y  threat x,y              23 heading | last_action << 4
    24-25 eaten  26-27 caught  28-29 jumps
    30-35 last motor window: ESC, BACK, FWD, STEER_L, STEER_R, FEED spike counts
    36-99 activity: 256 x 2-bit saturating spike counts since the last snapshot
          (neuron 4k+m in bits 2m+1..2m of byte 36+k)
    100   first probed neuron (8 * probe group)
    101-116 potentials of the 8 probed neurons (u16)
    117-118 CRC-16/CCITT-FALSE over bytes 2..116
"""

import struct

SYNC = b"\xA5\x5A"
VERSION = 2
BODY_LEN = 117
PAYLOAD_LEN = BODY_LEN - 4
PACKET_LEN = BODY_LEN + 2
N_ACT = 256

FLAG_RUNNING = 0x01
FLAG_FOOD = 0x02
FLAG_THREAT = 0x04
FLAG_DROPPED = 0x08
FLAG_SYSTOLIC = 0x10

# Layout of bytes 4..116 (after the 4-byte header, before the CRC)
_BODY = struct.Struct("<HIBHI6BB3H6B64sB16s")
assert _BODY.size == PAYLOAD_LEN


def crc16_ccitt_false(data, crc=0xFFFF):
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def encode(fields):
    """fields: dict with keys matching `decode` output. Returns PACKET_LEN bytes."""
    counts = fields["activity"]
    act = bytes(sum(min(counts[4 * k + m], 3) << (2 * m) for m in range(4)) for k in range(64))
    pots = struct.pack("<8H", *fields["potentials"])
    body = _BODY.pack(fields["seq"] & 0xFFFF, fields["step"] & 0xFFFFFFFF, fields["flags"],
                      fields["dropped_total"], fields["cycles"],
                      *fields["fly"], *fields["food"], *fields["threat"],
                      (fields["heading"] & 7) | ((fields["action"] & 7) << 4),
                      fields["eaten"] & 0xFFFF, fields["caught"] & 0xFFFF, fields["jumps"] & 0xFFFF,
                      *fields["motor"], act, fields["probe_base"], pots)
    covered = bytes([VERSION, PAYLOAD_LEN]) + body
    crc = crc16_ccitt_false(covered)
    return SYNC + covered + struct.pack("<H", crc)


def decode(pkt):
    """Decode one complete, CRC-checked packet into a dict."""
    (seq, step, flags, dropped, cycles, fx, fy, gx, gy, tx, ty, ha, eaten, caught, jumps,
     m0, m1, m2, m3, m4, m5, act, probe, pots) = _BODY.unpack(pkt[4:BODY_LEN])
    activity = []
    for b in act:
        activity += [(b >> (2 * m)) & 3 for m in range(4)]
    return {
        "seq": seq, "step": step, "flags": flags, "dropped_total": dropped, "cycles": cycles,
        "fly": (fx, fy), "food": (gx, gy), "threat": (tx, ty),
        "heading": ha & 7, "action": (ha >> 4) & 7,
        "eaten": eaten, "caught": caught, "jumps": jumps,
        "motor": (m0, m1, m2, m3, m4, m5), "activity": activity,
        "probe_base": probe, "potentials": list(struct.unpack("<8H", pots)),
    }


class PacketParser:
    """Byte-stream parser tolerant of partial reads, garbage, and corruption.

    feed(bytes) returns a list of decoded packets. On any header/CRC mismatch it
    drops exactly one byte and rescans, so a false sync pattern inside a payload
    never costs more than one byte of resynchronization.
    """

    def __init__(self):
        self.buf = bytearray()
        self.good = 0
        self.crc_errors = 0
        self.header_errors = 0
        self.discarded_bytes = 0
        self.seq_gaps = 0
        self.last_seq = None

    def feed(self, data):
        self.buf += data
        out = []
        while True:
            idx = self.buf.find(SYNC)
            if idx < 0:
                keep = 1 if self.buf[-1:] == SYNC[:1] else 0
                self.discarded_bytes += len(self.buf) - keep
                del self.buf[:len(self.buf) - keep]
                return out
            if idx:
                self.discarded_bytes += idx
                del self.buf[:idx]
            if len(self.buf) < 4:
                return out
            if self.buf[2] != VERSION or self.buf[3] != PAYLOAD_LEN:
                self.header_errors += 1
                self._drop_one()
                continue
            if len(self.buf) < PACKET_LEN:
                return out
            pkt = bytes(self.buf[:PACKET_LEN])
            crc_rx = pkt[BODY_LEN] | (pkt[BODY_LEN + 1] << 8)
            if crc16_ccitt_false(pkt[2:BODY_LEN]) != crc_rx:
                self.crc_errors += 1
                self._drop_one()
                continue
            del self.buf[:PACKET_LEN]
            fields = decode(pkt)
            if self.last_seq is not None and fields["seq"] != (self.last_seq + 1) & 0xFFFF:
                self.seq_gaps += 1
            self.last_seq = fields["seq"]
            self.good += 1
            out.append(fields)

    def _drop_one(self):
        del self.buf[:1]
        self.discarded_bytes += 1
