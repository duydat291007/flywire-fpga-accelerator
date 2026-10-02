#!/usr/bin/env python3
"""Check a raw telemetry byte capture for link-level integrity.

usage: check_stream.py BYTES_FILE [--min-packets N]

Passes if the stream parses with no CRC/header errors and no sequence gaps
except across a reset (sequence restarting at 0), and at least N packets were
decoded. A reset abandons the packet being transmitted, so each reset may
truncate one packet: --resets R allows up to R CRC/header errors. Used for board-level smoke tests where the exact model state is not
reproduced (step timing depends on the pacing timer).
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "model"))
from fly_model.packet import PacketParser          # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bytes_file")
    ap.add_argument("--min-packets", type=int, default=1)
    ap.add_argument("--resets", type=int, default=0, help="resets during the capture")
    a = ap.parse_args()
    data = bytes(int(x, 16) for x in pathlib.Path(a.bytes_file).read_text().split())
    p = PacketParser()
    pkts = p.feed(data)
    resets = sum(1 for prev, cur in zip(pkts, pkts[1:]) if cur["seq"] == 0 and prev["seq"] != 0xFFFF)
    gaps = p.seq_gaps - resets
    ok = p.crc_errors + p.header_errors <= a.resets and gaps == 0 and len(pkts) >= a.min_packets
    print(f"{'PASS' if ok else 'FAIL'} check_stream: {len(pkts)} packets, crc_err={p.crc_errors} "
          f"hdr_err={p.header_errors} seq_gaps={gaps} resets={resets} "
          f"steps {pkts[0]['step'] if pkts else '-'}..{max((x['step'] for x in pkts), default='-')}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
