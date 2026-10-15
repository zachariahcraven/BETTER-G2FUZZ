#!/usr/bin/env python3
"""Crash triage: replay every saved crash on the target's AddressSanitizer build and group the
crashes into unique bugs (same ASan error kind + same top 3 frames in the target's own code).

Runs inside the g2fuzz image with the workspace overlay (experiments/analysis/crash-triage starts it):
    python3 experiments/analysis/lib/crash_triage.py [campaign ...]     (default: every results/campaigns/*/<prefix>-<model>-r<N>)
Writes results/tables/crashes.csv (one row per crash file) and prints the unique bugs per target and which
models found them. Replays are cached in results/cache/triage-cache.json, so reruns only replay new crashes.
Replay settings match AFL++'s run: a 1 GB allocation limit (allocations over it return NULL, as
under `afl-fuzz -m 1024`), no leak checks, 20 s per crash.
"""
import csv, glob, json, os, re, subprocess, sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
os.chdir(ROOT)
TARGET = {"lineup": "jhead", "tiff": "tiff_read_rgba_fuzzer", "png": "libpng_read_fuzzer",
          "xml": "xml_fuzzer", "wad": "doom_wad"}
NAME = re.compile(r"(lineup|tiff|png|xml|wad)(\d+h)?-(.+)-r(\d+)$")   # optional run tag, e.g. wad4h
BANDIT = re.compile(r"bandit-(jhead|tiff|png|xml|wad)-(\w+)-r(\d+)$")   # scheduler runs: model sched-<sched>
TAG = {"jhead": "lineup", "tiff": "tiff", "png": "png", "xml": "xml", "wad": "wad"}
ENV = dict(os.environ,
           ASAN_OPTIONS="detect_leaks=0:allocator_may_return_null=1:max_allocation_size_mb=1024:symbolize=1",
           ASAN_SYMBOLIZER_PATH="/usr/lib/llvm-16/bin/llvm-symbolizer",
           G2F_DOOM_IWAD="/targets/freedoom2.wad")
FRAME = re.compile(r"^\s*#(\d+) 0x[0-9a-f]+ in (\S+) (\S+?):(\d+)")


def signature(stderr):
    """(kind, 'func file:line | ...') from an ASan report, or None if there is none."""
    m = re.search(r"ERROR: AddressSanitizer: ([\w-]+)", stderr)
    if not m:
        return None
    frames = []
    for line in stderr.splitlines():
        f = FRAME.match(line)
        if not f:
            continue
        func, path = f.group(2), f.group(3)
        if "/compiler-rt/" in path or "sanitizer" in path or path.startswith("/usr/"):
            continue   # ASan runtime and libc frames: not the target's code
        frames.append("%s %s:%s" % (func, os.path.basename(path), f.group(4)))
        if len(frames) == 3:
            break
    return m.group(1), " | ".join(frames) or "(no frames in the target's code)"


def replay(target, path):
    try:
        r = subprocess.run(["/targets/%s.asan" % target, path], capture_output=True, text=True,
                           errors="replace", env=ENV, timeout=20)
    except subprocess.TimeoutExpired:
        return "hang", ""
    sig = signature(r.stderr)
    if sig:
        return sig
    # a signal shows as a negative return code, or 129-159 from a shell; 255 is a normal error
    # exit (Doom's I_Error calls exit(-1)), not a crash
    if r.returncode < 0 or 128 < r.returncode < 160:
        return "signal-%d" % (-r.returncode if r.returncode < 0 else r.returncode - 128), ""
    return "no-repro", ""


cache_path = "results/cache/triage-cache.json"
cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
# entries from before the exit-255 fix: replay them again
cache = {k: v for k, v in cache.items() if v[0] != "signal-127"}
names = sys.argv[1:] or sorted(os.path.basename(d) for d in glob.glob("results/campaigns/*/*-*-r*") if "/archive/" not in d)
rows = []
for name in names:
    m = NAME.match(name)
    b = BANDIT.match(name)
    if b:
        prefix, model, rep = TAG[b.group(1)], "sched-" + b.group(2), b.group(3)
    elif m:
        prefix, model, rep = m.group(1), m.group(3), m.group(4)
    else:
        continue
    target = TARGET[prefix]
    if m and not b and m.group(2):
        prefix += m.group(2)   # tagged runs are reported as their own target, e.g. wad4h
    for path in sorted(glob.glob("results/campaigns/*/%s/*_output/default/crashes/id:*" % name)):
        if "/archive/" in path:
            continue
        key = "%s %d" % (path, os.path.getsize(path))
        if key not in cache:
            cache[key] = list(replay(target, os.path.abspath(path)))
        kind, frames = cache[key]
        rows.append({"campaign": name, "target": prefix, "model": model, "rep": rep,
                     "crash": os.path.basename(path), "kind": kind, "frames": frames})
    json.dump(cache, open(cache_path, "w"))

with open("results/tables/crashes.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["campaign", "target", "model", "rep", "crash", "kind", "frames"])
    w.writeheader()
    w.writerows(rows)

bugs = defaultdict(lambda: defaultdict(set))   # target -> (kind, frames) -> models
files = defaultdict(int)
for r in rows:
    files[r["target"]] += 1
    if r["kind"] not in ("no-repro", "hang"):
        bugs[r["target"]][(r["kind"], r["frames"])].add(r["model"])
for target in sorted(files):
    nr = sum(1 for r in rows if r["target"] == target and r["kind"] == "no-repro")
    # conservative count: one bug per crash site (error kind + top frame), whatever the callers
    sites = {(k, fr.split(" | ")[0]) for k, fr in bugs[target]}
    print("== %s: %d crash files, %d unique crash sites (%d distinct top-3 stacks), %d did not reproduce"
          % (target, files[target], len(sites), len(bugs[target]), nr))
    by_model = defaultdict(set)
    for (k, fr), models in bugs[target].items():
        for mo in models:
            by_model[mo].add((k, fr.split(" | ")[0]))
    print("  crash sites per model: " + ", ".join("%s %d" % (mo, len(v)) for mo, v in sorted(by_model.items(), key=lambda kv: -len(kv[1]))))
    for (kind, frames), models in sorted(bugs[target].items(), key=lambda kv: -len(kv[1])):
        print("  %-22s %-70s found by: %s" % (kind, frames[:70], ", ".join(sorted(models))))
print("\nper-crash rows: results/tables/crashes.csv")
