#!/usr/bin/env python3
"""Stock seeds for doom_demo: the demos that ship in freedoom2.wad (DEMO1-DEMO4, Doom v1.9 format),
each cut to its first TICS tics and closed with the 0x80 end marker.

Usage: make-demo-seeds.py [--tics N] [WAD] [OUT_DIR]   (defaults: 105, freedoom2.wad, demo-seeds/)
Deterministic: the same WAD and N always give the same bytes.
"""
import argparse
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
HEADER = 13


def lumps(path):
    data = open(path, "rb").read()
    magic, n, off = struct.unpack("<4sii", data[:12])
    assert magic in (b"IWAD", b"PWAD"), "not a WAD: %s" % path
    for i in range(n):
        pos, size, name = struct.unpack("<ii8s", data[off + 16 * i: off + 16 * i + 16])
        yield name.rstrip(b"\0").decode("ascii", "replace"), data[pos:pos + size]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tics", type=int, default=105)
    ap.add_argument("wad", nargs="?", default=os.path.join(HERE, "freedoom2.wad"))
    ap.add_argument("out", nargs="?", default=os.path.join(HERE, "demo-seeds"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    found = 0
    for name, lump in lumps(a.wad):
        if not (name.startswith("DEMO") and name[4:].isdigit()):
            continue
        players = sum(1 for b in lump[9:13] if b)
        body = lump[HEADER:]
        # a tic is 4 bytes per player; the marker can only start a tic, so search tic by tic
        tics = 0
        while 4 * players * (tics + 1) <= len(body) and tics < a.tics:
            if any(body[4 * players * tics + 4 * p] == 0x80 for p in range(players)):
                break
            tics += 1
        seed = lump[:HEADER] + body[:4 * players * tics] + bytes([0x80])
        out = os.path.join(a.out, "freedoom2-%s.lmp" % name.lower())
        open(out, "wb").write(seed)
        print("%s: map %d, %d player(s), %d tics -> %s (%d bytes)" % (
            name, lump[3], players, tics, os.path.basename(out), len(seed)))
        found += 1
    if not found:
        raise SystemExit("no DEMOn lumps in %s" % a.wad)


if __name__ == "__main__":
    main()
