#!/usr/bin/env python3
"""Headline coverage figure for a presentation, from replayed final queue coverage."""
import argparse
import csv
import os
import statistics
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

MODEL_COLORS = [
    "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
    "#8c564b", "#e377c2", "#bcbd22", "#17becf", "#aec7e8",
]


def parse_args():
    p = argparse.ArgumentParser(description="Replay coverage plot")
    p.add_argument("--csv", default="results/tables/cov-results.csv")
    p.add_argument("--out", default="results/figures")
    return p.parse_args()


def load_data(path):
    """Return {target: {model: [queue_edges, ...]}} after filtering."""
    if not os.path.exists(path):
        print("Error: %s not found" % path, file=sys.stderr)
        sys.exit(0)
    groups = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            model = row.get("model", "")
            if model.startswith("sched-"):
                continue
            try:
                qe = int(row["queue_edges"])
            except (ValueError, KeyError, TypeError):
                print("Warning: skipping %s (non-integer queue_edges)"
                      % row.get("campaign", "?"), file=sys.stderr)
                continue
            groups.setdefault(row.get("target", ""), {}).setdefault(model, []).append(qe)
    return groups


def fmt_median(x):
    return str(int(x)) if x == int(x) else "%.1f" % x


def model_order(models):
    """Return (ordered_model_names, {model: median})."""
    med = {m: statistics.median(v) for m, v in models.items()}
    b = med.get("baseline")
    order = (["baseline"] if b is not None else []) + sorted(
        (m for m in med if m != "baseline"), key=lambda m: (-med[m], m)
    )
    return order, med


def write_gain_csv(groups, out_dir):
    rows = []
    for target in sorted(groups):
        order, med = model_order(groups[target])
        b = med.get("baseline")
        for m in order:
            runs = len(groups[target][m])
            if b is None or m == "baseline":
                gain = ""
            else:
                gain = "%.1f" % round(100.0 * (med[m] - b) / b, 1)
            rows.append([target, m, str(runs), fmt_median(med[m]), gain])
    with open(os.path.join(out_dir, "replay_gain.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["target", "model", "runs", "median_edges", "gain_pct"])
        w.writerows(rows)


def make_figure(target, models, out_dir):
    order, med = model_order(models)
    b = med.get("baseline")
    n = len(order)
    fig, ax = plt.subplots(figsize=(max(9.0, n * 2.5), 6.0), dpi=100)

    colors = {}
    color_idx = 0
    for i, m in enumerate(order):
        vals = models[m]
        if m == "baseline":
            color = "gray"
        elif m.startswith("ctl-"):
            color = "#9a9a9a"
        else:
            color = MODEL_COLORS[color_idx % len(MODEL_COLORS)]
            color_idx += 1
        colors[m] = color

        nv = len(vals)
        for j, v in enumerate(vals):
            offset = (j - (nv - 1) / 2.0) * 0.06
            ax.plot(i + offset, v, "o", color=color, markersize=5, alpha=0.7)
        ax.hlines(med[m], i - 0.15, i + 0.15, color=color, linewidth=3)

    max_val = max(max(v) for v in models.values())
    ylim_top = max_val * 1.25
    ax.set_ylim(0, ylim_top)

    if b is not None:
        ax.axhline(y=b, color="gray", linestyle="--", linewidth=1, alpha=0.6)
        for i, m in enumerate(order):
            if m == "baseline":
                continue
            gain_pct = 100.0 * (med[m] - b) / b
            max_dot = max(models[m])
            label_y = max_dot + 0.02 * ylim_top
            ax.text(i, label_y, "%+.1f%%" % gain_pct, ha="center", va="bottom",
                    fontsize=14, fontweight="bold", color=colors[m])

    ax.set_ylabel("edges (final queue, replayed)", fontsize=14)
    ax.set_xticks(range(n))
    ax.set_xticklabels(order)
    ax.tick_params(axis="both", labelsize=13)
    for label, m in zip(ax.get_xticklabels(), order):
        if m.startswith("ctl-"):
            label.set_color("#9a9a9a")
            label.set_style("italic")
    ax.set_title(target, fontsize=18)
    plt.tight_layout()
    fig.savefig(os.path.join(out_dir, "replay_%s.png" % target), dpi=100)
    plt.close(fig)


def main():
    args = parse_args()
    groups = load_data(args.csv)
    os.makedirs(args.out, exist_ok=True)
    write_gain_csv(groups, args.out)
    for target in sorted(groups):
        make_figure(target, groups[target], args.out)


if __name__ == "__main__":
    main()
