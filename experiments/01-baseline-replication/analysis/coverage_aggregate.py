#!/usr/bin/env python3
"""Turns one campaign's per-file afl-showmap maps into coverage numbers (called by 01-coverage.sbatch).

Input: the campaign's queue folder (file names id:NNNNNN,time:<ms>,...; initial seeds carry orig:<name> and time:0)
and a folder of afl-showmap outputs with the same file names ("<edge>:<hits>" per line).
Output: <out>/<campaign>.json and <out>/edges/<campaign>.txt.gz (sorted edge ids).
  edges_final  union of the edges of every replayed queue file
  edges_seeds  union over the initial seeds only (orig: files): stock seeds + LLM seeds for the G2FUZZ arms
  edges_at     cumulative edges at 900, 1800, ... 21600 s, from each file's time: stamp (ms since afl-fuzz started)
  queue_files / replayed / not_replayed (timed out or failed in afl-showmap) / over_1mb (afl-showmap reads the first
  1 MB of larger files, the same for every arm)
"""
import argparse, gzip, json, os, re, sys

p = argparse.ArgumentParser()
for a in ("campaign", "program", "arm", "rep", "queue", "maps", "out"): p.add_argument("--" + a, required=True)
p.add_argument("--secs", type=int, default=21600, help="the campaign's fuzzing time (-V); edges_at buckets run up to it")
a = p.parse_args()
TIME = re.compile(r",time:(\d+)")
BUCKETS = list(range(900, a.secs + 1, 900))

files = sorted(f for f in os.listdir(a.queue) if f.startswith("id:"))
rows = []  # (time_s, is_seed, edges set or None)
over_1mb = 0
for f in files:
    m = TIME.search(f); t = int(m.group(1)) / 1000 if m else 0.0
    if os.path.getsize(os.path.join(a.queue, f)) > 1 << 20: over_1mb += 1
    mp = os.path.join(a.maps, f); edges = None
    if os.path.isfile(mp):
        with open(mp) as h: edges = {int(l.split(":")[0]) for l in h if l.strip()}
    rows.append((t, ",orig:" in f, edges))
rows.sort(key=lambda r: r[0])

final, seeds, at = set(), set(), {}
bi = 0
for t, is_seed, edges in rows:
    while bi < len(BUCKETS) and t > BUCKETS[bi]: at[BUCKETS[bi]] = len(final); bi += 1
    if edges is None: continue
    final |= edges
    if is_seed: seeds |= edges
while bi < len(BUCKETS): at[BUCKETS[bi]] = len(final); bi += 1

res = dict(campaign=a.campaign, program=a.program, arm=a.arm, rep=int(a.rep), queue_files=len(files),
           replayed=sum(1 for r in rows if r[2] is not None), not_replayed=sum(1 for r in rows if r[2] is None),
           over_1mb=over_1mb, seed_files=sum(1 for r in rows if r[1]), edges_final=len(final), edges_seeds=len(seeds),
           edges_at={str(k): v for k, v in at.items()})
os.makedirs(os.path.join(a.out, "edges"), exist_ok=True)
with open(os.path.join(a.out, a.campaign + ".json"), "w") as h: json.dump(res, h, indent=1)
with gzip.open(os.path.join(a.out, "edges", a.campaign + ".txt.gz"), "wt") as h: h.write("\n".join(map(str, sorted(final))) + "\n")
print(f"{a.campaign}: {res['replayed']}/{len(files)} replayed, edges_final {len(final)}, edges_seeds {len(seeds)}, "
      f"at 1h/3h/end {at.get(3600)}/{at.get(10800)}/{at[BUCKETS[-1]]}, not_replayed {res['not_replayed']}, over_1mb {over_1mb}")
