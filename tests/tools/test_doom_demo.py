#!/usr/bin/env python3
"""Acceptance test for doom_demo.py, written by the judge during the butler work (2026-10).
Run from anywhere, with Pillow and matplotlib.
Fixture: real Doom fuzzing results in tests/fixtures/doomdemo2 (10 crash sites from triage:
5 the baseline did not find, one of them with no stack trace, and 5 it did; generated seeds from the models).
"""
import csv, json, os, subprocess, sys, tempfile

from PIL import Image, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.join(ROOT, "experiments/analysis/lib"))   # the tool under test runs from its own folder
FIX = os.path.join(ROOT, "tests/fixtures/doomdemo2")
OUT = tempfile.mkdtemp(prefix="doomdemo_")
failures = []


def check(cond, msg):
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        failures.append(msg)


r = subprocess.run([sys.executable, "doom_demo.py", "--eval", FIX + "/campaigns", "--crashes", FIX + "/exp/crashes.csv",
                    "--stock", FIX + "/seeds/wad", "--out", OUT], capture_output=True, text=True, timeout=600)
check(r.returncode == 0 and "Traceback" not in r.stderr, "doom_demo.py exits 0 (stderr: %s)" % r.stderr.strip()[-300:])

# figure 1: crash maps
tiles = json.load(open(os.path.join(OUT, "crash_maps.json"))) if os.path.exists(os.path.join(OUT, "crash_maps.json")) else []
sites = {(row["kind"], row["frames"].split(" | ")[0]) for row in csv.DictReader(open(FIX + "/exp/crashes.csv"))
         if row["target"] == "wad" and row["kind"] not in ("no-repro", "hang")}
check(len(tiles) == len(sites) == 10, "crash_maps.json lists one tile per crash site (%d of %d)" % (len(tiles), len(sites)))
check({(t.get("kind"), t.get("frame")) for t in tiles} == sites, "the tiles are exactly the triaged crash sites")
check(all(t.get("models") for t in tiles), "every tile lists the models that found it")
check(all(not m.startswith("sched-") for t in tiles for m in t.get("models", [])), "no sched-* arms in the model lists")
base = [("baseline" in t.get("models", [])) for t in tiles]
check(base == sorted(base), "sites the baseline did not find come first (baseline flags in order: %s)" % base)
for flag in (False, True):
    kinds = [t.get("kind") for t, b in zip(tiles, base) if b == flag]
    check(len(set(kinds[:len(set(kinds))])) == len(set(kinds)),
          "baseline=%s group: one tile per crash kind comes first (kinds in order: %s)" % (flag, kinds))
for t in tiles:
    want_title = "%s (no stack trace)" % t.get("kind") if not t.get("frame") else "%s in %s" % (t.get("kind"), t.get("frame"))
    check(t.get("title") == want_title, "tile %s: title %r (got %r)" % (t.get("frame"), want_title, t.get("title")))
    only = "baseline" not in t.get("models", [])
    fb = t.get("found_by", "")
    check(fb.startswith("found by: ") and fb.endswith(" (LLM runs only)") == only,
          "tile %s: found_by ends with ' (LLM runs only)' exactly when the baseline did not find it (got %r)" % (t.get("frame"), fb))
stock = [open(os.path.join(FIX, "seeds/wad", f), "rb").read() for f in sorted(os.listdir(FIX + "/seeds/wad"))]
def changed(path):
    d = open(path, "rb").read()
    same = [sum(a != b for a, b in zip(d, s)) for s in stock if len(s) == len(d)]
    return min(same) if same else None
for t in tiles:
    want = changed(t.get("file", "")) if os.path.isfile(t.get("file", "")) else "missing"
    check(t.get("bytes_changed", "absent") == want, "tile %s: bytes_changed = %s (got %s)" % (t.get("frame"), want, t.get("bytes_changed", "absent")))
for t in tiles:
    f = t.get("file", "")
    ok = os.path.isfile(f) and "/crashes/" in f
    if ok:
        m = subprocess.run([sys.executable, "wad_map.py", f, t.get("map", ""), "-o", os.path.join(OUT, "chk.png"), "--size", "200"],
                           capture_output=True, timeout=120)
        ok = m.returncode == 0
    check(ok, "tile %s: its crash file exists and its map renders independently" % t.get("frame"))
p = os.path.join(OUT, "crash_maps.png")
if os.path.exists(p):
    im = Image.open(p).convert("L")
    w, h = im.size
    check(w >= 1200 and h >= 4 * 500, "crash_maps.png is at least 1200x2000 for 4 rows of 3 tiles (got %dx%d)" % (w, h))
    # each 400x400 map area must contain a drawing, not a flat placeholder (one degenerate fuzzed map may look flat)
    flat = [i for i in range(10) if ImageStat.Stat(im.crop(((i % 3) * w // 3, (i // 3) * h // 4, (i % 3) * w // 3 + 380,
                                                             (i // 3) * h // 4 + 380))).stddev[0] < 8]
    check(len(flat) <= 1, "tile areas have a drawing in them (flat tiles: %s)" % flat)
else:
    check(False, "crash_maps.png exists")

# figure 2: generated-seed validity, computed here independently
exp = {}
for c in os.listdir(FIX + "/campaigns/fixture"):
    model = c.split("-", 1)[1].rsplit("-r", 1)[0]
    if model == "baseline":
        continue
    for f in os.listdir(os.path.join(FIX, "campaigns/fixture", c, "initial_seeds")):
        if f.startswith("freedoom2-"):
            continue
        e = exp.setdefault(model, [0, 0, 0])
        e[0] += 1
        e[1] += open(os.path.join(FIX, "campaigns/fixture", c, "initial_seeds", f), "rb").read(4) in (b"IWAD", b"PWAD")
got = {}
p = os.path.join(OUT, "wad_validity.csv")
if os.path.exists(p):
    got = {row["model"]: [int(row["seeds"]), int(row["magic"]), int(row["renders"])] for row in csv.DictReader(open(p))}
check(set(got) == set(exp), "wad_validity.csv has every model with generated seeds, no baseline (got %s)" % sorted(got))
check(all(got.get(m, [0, 0])[:2] == v[:2] for m, v in exp.items()), "seed and IWAD/PWAD counts are right (want %s)" % exp)
check(all(got.get(m, [0, 0, -1])[2] == 0 for m in exp), "no fixture seed renders (they are all malformed), so renders is 0")
p = os.path.join(OUT, "wad_validity.png")
check(os.path.exists(p) and Image.open(p).size[0] >= 800, "wad_validity.png exists and is at least 800 px wide")

r2 = subprocess.run([sys.executable, "doom_demo.py", "--eval", tempfile.mkdtemp(), "--crashes", "/nonexistent.csv",
                     "--out", tempfile.mkdtemp()], capture_output=True, text=True, timeout=60)
check(r2.returncode == 0 and "Traceback" not in r2.stderr, "no inputs: exits 0, no traceback")

print("\noutput in", OUT)
print("%d failed" % len(failures) if failures else "all passed")
sys.exit(1 if failures else 0)
