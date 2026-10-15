#!/usr/bin/env python3
"""Stock seeds for the doom_wad target: Freedoom's smallest maps, each cut out of the base game into
its own add-on WAD (map marker renamed MAP01, the 10 map lumps byte for byte).

Usage: targets/doom/make-seeds.py [iwad] [out_dir] [count]   (defaults: targets/doom/freedoom2.wad targets/doom/seeds 8)
"""
import os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "freedoom2.wad")
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "seeds")
count = int(sys.argv[3]) if len(sys.argv) > 3 else 8

d = open(iwad, "rb").read()
n, off = struct.unpack("<ii", d[4:12])
ents = [struct.unpack("<ii8s", d[off + 16 * i: off + 16 * i + 16]) for i in range(n)]
names = [e[2].rstrip(b"\0") for e in ents]


def pwad(lumps):
    body, dirs, pos = b"", b"", 12
    for name, data in lumps:
        dirs += struct.pack("<ii8s", pos, len(data), name)
        body += data
        pos += len(data)
    return b"PWAD" + struct.pack("<ii", len(lumps), 12 + len(body)) + body + dirs


maps = []
for i, name in enumerate(names):
    if len(name) == 5 and name.startswith(b"MAP") and name[3:].isdigit() and names[i + 2] == b"LINEDEFS":
        lumps = [(b"MAP01", b"")] + [(names[j], d[ents[j][0]: ents[j][0] + ents[j][1]]) for j in range(i + 1, i + 11)]
        maps.append((len(pwad(lumps)), name.decode(), pwad(lumps)))
os.makedirs(out, exist_ok=True)
for size, name, data in sorted(maps)[:count]:
    with open(os.path.join(out, "freedoom2-%s.wad" % name.lower()), "wb") as f:
        f.write(data)
    print("%s %d bytes" % (name, size))
