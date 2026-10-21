#!/usr/bin/env python3
"""XML coverage over time (plan A4): is Coder-Next's gain a head start or lasting?

Reads results/figures/coverage.csv (written by plots.py from AFL++'s plot_data: AFL's own edge counter, which is
reliable for XML; Doom is the target where it is not) and draws the median edges per minute for the XML baseline
(1 h, 4 h and 12 h groups) and Coder-Next (1 h, 4 h) on one axis. Prints the median gain at 60, 240 and 720 min.
  ~/plotenv/bin/python experiments/analysis/lib/xml_time.py   -> results/figures/xml_over_time.png
Campaigns in experiments/inputs/exclusions.csv are already left out by plots.py.
"""
import csv
import statistics
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

SERIES = [("xml", "baseline", "baseline 1 h"), ("xml-4h", "baseline", "baseline 4 h"), ("xml-12h", "baseline", "baseline 12 h"),
          ("xml", "codernext", "Coder-Next 1 h"), ("xml-4h", "codernext", "Coder-Next 4 h")]


def main():
    runs = defaultdict(lambda: defaultdict(dict))   # (target, model) -> rep -> minute -> edges
    with open("results/figures/coverage.csv") as f:
        for r in csv.DictReader(f):
            runs[(r["target"], r["model"])][r["rep"]][int(r["minute"])] = int(r["edges"])
    med = {}
    fig, ax = plt.subplots(figsize=(10, 6))
    for target, model, label in SERIES:
        reps = runs.get((target, model))
        if not reps:
            print("missing series %s %s" % (target, model))
            continue
        minutes = sorted(set.intersection(*(set(m) for m in reps.values())))
        ys = [statistics.median(rep[t] for rep in reps.values()) for t in minutes]
        med[(target, model)] = dict(zip(minutes, ys))
        style = "-" if model == "codernext" else "--"
        ax.plot(minutes, ys, style, label="%s (n=%d)" % (label, len(reps)))
    ax.set_xscale("log")
    ax.set_xlabel("minutes of fuzzing (log scale)")
    ax.set_ylabel("edges (AFL++ counter, median of runs)")
    ax.set_title("XML: Coder-Next vs plain AFL++ over time")
    ax.legend()
    fig.tight_layout()
    fig.savefig("results/figures/xml_over_time.png", dpi=100)
    for t, base, cn in ((60, ("xml", "baseline"), ("xml", "codernext")), (240, ("xml-4h", "baseline"), ("xml-4h", "codernext"))):
        b, c = med.get(base, {}).get(t), med.get(cn, {}).get(t)
        if b and c:
            print("minute %d: baseline %s, Coder-Next %s, gain %+.1f%%" % (t, b, c, 100.0 * (c - b) / b))
    b12 = med.get(("xml-12h", "baseline"), {})
    for t in (60, 240, 720):
        if t in b12:
            print("baseline 12 h run at minute %d: %s" % (t, b12[t]))


if __name__ == "__main__":
    main()
