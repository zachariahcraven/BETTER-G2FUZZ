#!/usr/bin/env python3
"""Acceptance test for wad_map.py, written by the judge during the butler work (2026-10).

Run from anywhere, with Pillow:  uv run --with pillow==11.3.0 python <this file>
Uses targets/doom/freedoom2.wad (Freedoom 0.13.0, BSD; freedoom1.wad via FREEDOOM1_WAD) plus tiny WADs built here.
"""
import os, struct, subprocess, sys, tempfile, time

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.join(ROOT, "experiments/analysis/lib"))   # the tool under test runs from its own folder
FD2 = os.path.join(ROOT, "targets/doom/freedoom2.wad")
# freedoom1.wad (Doom 1 maps, 26 MB) is not in the repo: its checks run when FREEDOOM1_WAD names it
FD1 = os.environ.get("FREEDOOM1_WAD", "")
SCRIPT = os.path.join(os.getcwd(), "wad_map.py")
TMP = tempfile.mkdtemp(prefix="wad_map_test_")
failures = []


def run(*args):
    return subprocess.run([sys.executable, SCRIPT] + [str(a) for a in args], capture_output=True, text=True, timeout=120)


def check(cond, msg):
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        failures.append(msg)


def wad(lumps, kind=b"PWAD"):
    """A WAD file from (name, bytes) pairs."""
    data, dirs, pos = b"", b"", 12
    for name, body in lumps:
        dirs += struct.pack("<ii8s", pos, len(body), name.encode())
        data += body
        pos += len(body)
    return kind + struct.pack("<ii", len(lumps), 12 + len(data)) + data + dirs


def map_wad(verts, lines, things=()):
    """A one-map PWAD (MAP01). lines: (v1, v2, one_sided)."""
    vx = b"".join(struct.pack("<hh", x, y) for x, y in verts)
    ld = b"".join(struct.pack("<HHHHHHH", a, b, 1 if one else 4, 0, 0, i, 0xFFFF if one else i)
                  for i, (a, b, one) in enumerate(lines))
    sd = b"".join(struct.pack("<hh8s8s8sH", 0, 0, b"-", b"-", b"STARTAN3", 0) for _ in lines)
    se = struct.pack("<hh8s8shhh", 0, 128, b"FLOOR0_1", b"CEIL1_1", 160, 0, 0)
    th = b"".join(struct.pack("<hhhhh", x, y, 0, t, 7) for x, y, t in things)
    return wad([("MAP01", b""), ("THINGS", th), ("LINEDEFS", ld), ("SIDEDEFS", sd), ("VERTEXES", vx),
                ("SEGS", b""), ("SSECTORS", b""), ("NODES", b""), ("SECTORS", se), ("REJECT", b""), ("BLOCKMAP", b"")])


def write(name, data):
    p = os.path.join(TMP, name)
    with open(p, "wb") as f:
        f.write(data)
    return p


def line_pixels(path):
    """(width, height, colours, pixels that differ from the background colour, those pixels' (x, y))."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    counts = {}
    for y in range(h):
        for x in range(w):
            counts[px[x, y]] = counts.get(px[x, y], 0) + 1
    bg = max(counts, key=counts.get)
    pts = [(x, y) for y in range(h) for x in range(w) if px[x, y] != bg]
    return w, h, len(counts), pts


def clean_failure(r, what):
    check(r.returncode == 2, "%s: exits with status 2 (got %d)" % (what, r.returncode))
    check("Traceback" not in r.stderr and "wad_map:" in r.stderr, "%s: one 'wad_map: ...' message, no traceback" % what)


# --list
r = run(FD2, "--list")
check(r.returncode == 0 and "MAP01" in r.stdout.split() and "MAP32" in r.stdout.split(), "--list freedoom2.wad shows MAP01..MAP32")
if FD1:
    r = run(FD1, "--list")
    check(r.returncode == 0 and "E1M1" in r.stdout.split(), "--list freedoom1.wad shows E1M1")
else:
    print("skip  freedoom1.wad checks (set FREEDOOM1_WAD to run them)")

# real maps
out = os.path.join(TMP, "map01.png")
t = time.time()
r = run(FD2, "MAP01", "-o", out, "--size", 800)
check(r.returncode == 0 and os.path.isfile(out), "freedoom2 MAP01 renders (stderr: %s)" % r.stderr.strip()[:200])
check(time.time() - t < 10, "MAP01 renders in under 10 s")
if os.path.isfile(out):
    w, h, colours, pts = line_pixels(out)
    check(max(w, h) == 800, "--size 800 sets the longer side to 800 (got %dx%d)" % (w, h))
    check(len(pts) > 2000, "MAP01 has drawn lines (%d pixels)" % len(pts))
    check(colours >= 3, "one-sided and two-sided lines differ in colour (%d colours)" % colours)
out = os.path.join(TMP, "e1m1.png")
if FD1:
    r = run(FD1, "E1M1", "-o", out)
    check(r.returncode == 0 and os.path.isfile(out) and max(Image.open(out).size) == 1024,
          "freedoom1 E1M1 renders at the default size 1024")

# a tiny hand-made map: a triangle with its apex at the top (Doom's y axis points up)
tri = write("tri.wad", map_wad([(0, 0), (512, 0), (256, 512)], [(0, 1, True), (1, 2, True), (2, 0, True)],
                               things=[(256, 128, 1)]))
out = os.path.join(TMP, "tri.png")
r = run(tri, "MAP01", "-o", out, "--size", 400)
check(r.returncode == 0 and os.path.isfile(out), "hand-made PWAD renders (stderr: %s)" % r.stderr.strip()[:200])
if os.path.isfile(out):
    w, h, colours, pts = line_pixels(out)
    ys = sorted(y for _, y in pts)
    top, bottom = ys[0], ys[-1]
    span = lambda rows: (lambda xs: max(xs) - min(xs) if xs else 0)([x for x, y in pts if y in rows])
    band = max(2, (bottom - top) // 10)
    check(span(range(top, top + band)) < span(range(bottom - band, bottom + 1)),
          "map is not upside down (the triangle's apex is at the top of the image)")
r = run(tri, "--list")
check(r.returncode == 0 and r.stdout.split() == ["MAP01"], "--list on a PWAD shows just its map")

# robustness: the renderer will be shown fuzzed WADs
bad = write("badline.wad", map_wad([(0, 0), (256, 0), (256, 256), (0, 256)],
                                   [(0, 1, True), (1, 2, True), (2, 3, True), (3, 999, True)]))
r = run(bad, "MAP01", "-o", os.path.join(TMP, "bad.png"))
check(r.returncode == 0 and "warning" in r.stderr.lower() and "Traceback" not in r.stderr,
      "a line with a missing vertex is skipped with a warning; the rest still renders")
clean_failure(run(FD2, "E9M9", "-o", os.path.join(TMP, "x.png")), "a map the WAD doesn't have")
clean_failure(run(write("trunc.wad", open(FD2, "rb").read(1000)), "--list"), "a truncated WAD")
clean_failure(run(write("garbage.wad", bytes((i * 131 + 7) % 256 for i in range(4096))), "--list"), "a garbage file")
clean_failure(run(write("huge.wad", b"PWAD" + struct.pack("<ii", 2**31 - 1, 12)), "--list"), "a header claiming 2^31 lumps")
clean_failure(run(os.path.join(TMP, "missing.wad"), "--list"), "a file that doesn't exist")
empty = write("empty.wad", map_wad([], []))
clean_failure(run(empty, "MAP01", "-o", os.path.join(TMP, "e.png")), "a map with no lines")

print("\n%d failed" % len(failures) if failures else "\nall passed")
sys.exit(1 if failures else 0)
