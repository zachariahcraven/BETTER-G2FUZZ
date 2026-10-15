#!/usr/bin/env python3
"""Generate presentation figures and a tidy CSV from G2Fuzz fuzzing campaigns."""

import argparse
import csv
import glob
import json
import os
import re
import statistics
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

PALETTE = [
    "tab:blue",
    "tab:orange",
    "tab:green",
    "tab:red",
    "tab:purple",
    "tab:brown",
    "tab:pink",
    "tab:gray",
    "tab:olive",
    "tab:cyan",
]

CAMPAIGN_RE = re.compile(r"^(lineup|tiff|png|xml|wad)(\d+h)?-(.+)-r(\d+)$")   # optional run tag, e.g. xml4h
BANDIT_RE = re.compile(r"^bandit-(.+)-r(\d+)$")


def as_float(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def parse_campaign_name(name):
    if name.startswith("bandit-"):
        m = BANDIT_RE.match(name)
        if not m:
            return None
        rest = m.group(1)
        rep = int(m.group(2))
        if "-" not in rest:
            return None
        tag, sched = rest.rsplit("-", 1)
        if not tag or not sched:
            return None
        return {"target": tag, "model": "sched-" + sched, "rep": rep, "sched": sched}

    m = CAMPAIGN_RE.match(name)
    if not m:
        return None
    prefix, tag, model, rep = m.group(1), m.group(2), m.group(3), int(m.group(4))
    if not model:
        return None
    target = ("jhead" if prefix == "lineup" else prefix) + ("-" + tag if tag else "")
    return {"target": target, "model": model, "rep": rep, "sched": None}


def find_output_dir(campaign_path):
    matches = [
        path
        for path in sorted(glob.glob(os.path.join(campaign_path, "*_output", "default")))
        if os.path.isdir(path)
    ]
    for path in matches:
        if os.path.isfile(os.path.join(path, "plot_data")):
            return path
    return matches[0] if matches else None


def parse_plot_data(path):
    rows = []
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = [part.strip() for part in line.split(",")]
                if len(parts) < 13:
                    continue
                try:
                    t = int(parts[0])
                    edges = int(parts[12])
                except ValueError:
                    continue
                rows.append((t, edges))
    except OSError:
        return []
    return rows


def parse_start_time(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                if ":" not in line:
                    continue
                key, value = line.split(":", 1)
                if key.strip() == "start_time":
                    try:
                        return int(value.strip())
                    except ValueError:
                        pass
    except OSError:
        pass
    return 0


def compute_series(rows):
    if not rows:
        return []

    max_t = max(t for t, _ in rows)
    max_min = max_t // 60 if max_t >= 0 else 0
    if max_min < 0:
        max_min = 0

    start_last = [-1] * (max_min + 1)
    for idx, (t, _edges) in enumerate(rows):
        if t <= 0:
            start_minute = 0
        else:
            start_minute = (t + 59) // 60
        if start_minute <= max_min:
            start_last[start_minute] = idx

    series = []
    current = -1
    for minute in range(max_min + 1):
        if start_last[minute] > current:
            current = start_last[minute]
        edges = rows[current][1] if current != -1 else 0
        series.append((minute, edges))
    return series


def load_campaigns(campaigns_dir):
    campaigns = []
    try:
        groups = sorted(os.listdir(campaigns_dir))
    except OSError:
        return campaigns

    for group in groups:
        if group == "archive":
            continue
        group_path = os.path.join(campaigns_dir, group)
        if not os.path.isdir(group_path):
            continue
        try:
            entries = sorted(os.listdir(group_path))
        except OSError:
            continue

        for name in entries:
            campaign_path = os.path.join(group_path, name)
            if not os.path.isdir(campaign_path):
                continue

            meta = parse_campaign_name(name)
            if meta is None:
                continue

            out_dir = find_output_dir(campaign_path)
            if out_dir is None:
                continue

            plot_path = os.path.join(out_dir, "plot_data")
            if not os.path.isfile(plot_path):
                continue

            rows = parse_plot_data(plot_path)
            if not rows:
                continue

            stats_path = os.path.join(out_dir, "fuzzer_stats")
            start_time = parse_start_time(stats_path) if os.path.isfile(stats_path) else 0

            scheduler_path = os.path.join(out_dir, "mutation_log", "scheduler.jsonl")
            scheduler_path = (
                scheduler_path
                if os.path.isfile(scheduler_path) and os.path.getsize(scheduler_path) > 0
                else None
            )

            series = compute_series(rows)
            if not series:
                continue

            campaigns.append(
                {
                    **meta,
                    "series": series,
                    "final_edges": series[-1][1],
                    "start_time": start_time,
                    "scheduler_path": scheduler_path,
                }
            )

    return campaigns


def write_coverage_csv(campaigns, out_dir):
    path = os.path.join(out_dir, "coverage.csv")
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["target", "model", "rep", "minute", "edges"])
        for camp in sorted(campaigns, key=lambda c: (c["target"], c["model"], c["rep"])):
            for minute, edges in camp["series"]:
                writer.writerow([camp["target"], camp["model"], camp["rep"], minute, edges])


def build_model_data(campaigns):
    data = {}
    for camp in campaigns:
        minute_map = data.setdefault(camp["target"], {}).setdefault(camp["model"], {})
        for minute, edges in camp["series"]:
            minute_map.setdefault(minute, []).append(edges)
    return data


def build_final_data(campaigns):
    data = {}
    for camp in campaigns:
        data.setdefault(camp["target"], {}).setdefault(camp["model"], []).append(camp["final_edges"])
    return data


def plot_coverage(data, title, path):
    fig, ax = plt.subplots(figsize=(10, 6), dpi=120)
    color_index = 0

    for model in sorted(data):
        minutes = sorted(data[model])
        if not minutes:
            continue

        medians = []
        lows = []
        highs = []
        for minute in minutes:
            values = data[model][minute]
            medians.append(statistics.median(values))
            lows.append(min(values))
            highs.append(max(values))

        if model == "baseline":
            color = "black"
            linestyle = "--"
        else:
            color = PALETTE[color_index % len(PALETTE)]
            linestyle = "-"
            color_index += 1

        ax.plot(minutes, medians, color=color, linestyle=linestyle, linewidth=2, label=model)
        ax.fill_between(minutes, lows, highs, color=color, alpha=0.2, linewidth=0, label=None)

    ax.set_xlabel("Minute")
    ax.set_ylabel("Edges found")
    ax.set_title(title)
    ax.grid(axis="y", alpha=0.3)
    handles, labels = ax.get_legend_handles_labels()
    if handles:
        ax.legend(handles, labels)

    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def plot_final_edges(data, path):
    targets = sorted(data)
    if not targets:
        return

    n = len(targets)
    fig, axes = plt.subplots(n, 1, figsize=(10, 6 * n), dpi=120, squeeze=False)
    axes = axes.flatten()

    for ax, target in zip(axes, targets):
        models = data[target]
        items = []
        for model, values in models.items():
            if not values:
                continue
            med = statistics.median(values)
            items.append((model, med, min(values), max(values)))

        items.sort(key=lambda item: (-item[1], item[0]))

        ax.set_ylabel("Final edges")
        ax.set_title(target)
        ax.grid(axis="y", alpha=0.3)

        if not items:
            continue

        x = list(range(len(items)))
        labels = []
        medians = []
        lowers = []
        uppers = []
        colors = []

        for model, med, low, high in items:
            labels.append(model)
            medians.append(med)
            lowers.append(med - low)
            uppers.append(high - med)
            colors.append("grey" if model == "baseline" else "tab:blue")

        ax.bar(x, medians, yerr=[lowers, uppers], capsize=4, color=colors, edgecolor="black", linewidth=0.8)
        ax.set_xticks(x)
        ax.set_xticklabels(labels, rotation=25, ha="right")

    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def posterior_mean(info):
    if not isinstance(info, dict):
        return 0.0
    a = as_float(info.get("a", 0))
    b = as_float(info.get("b", 0))
    denom = a + b
    if denom <= 0:
        return 0.0
    return a / denom


def load_scheduler_records(path):
    records = []
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(obj, dict):
                    records.append(obj)
    except OSError:
        return []

    records.sort(key=lambda r: as_float(r.get("time", 0)))
    return records


def plot_bandit(tag, campaign, out_dir):
    records = load_scheduler_records(campaign["scheduler_path"]) if campaign.get("scheduler_path") else []
    start = as_float(campaign.get("start_time", 0), 0.0)

    fig, axes = plt.subplots(2, 1, figsize=(10, 8), dpi=120, squeeze=False)
    axes = axes.flatten()

    for ax, kind in zip(axes, ("generator", "mutator")):
        steps = [r for r in records if r.get("kind") == kind]
        arm_series = {}
        final_means = {}

        for record in steps:
            time = as_float(record.get("time", start), start)
            minute = (time - start) / 60.0
            arms = record.get("arms", {})
            if not isinstance(arms, dict):
                arms = {}

            for arm, info in arms.items():
                arm_name = str(arm)
                mean = posterior_mean(info)
                arm_series.setdefault(arm_name, []).append((minute, mean))
                final_means[arm_name] = mean

        top_arms = [
            arm
            for arm, _mean in sorted(final_means.items(), key=lambda kv: (-kv[1], kv[0]))[:6]
        ]

        for idx, arm in enumerate(top_arms):
            series = sorted(arm_series.get(arm, []), key=lambda point: point[0])
            xs = [point[0] for point in series]
            ys = [point[1] for point in series]
            ax.plot(xs, ys, color=PALETTE[idx % len(PALETTE)], linewidth=1.6, label=arm)

        choice_x = []
        choice_y = []
        for record in steps:
            choice = record.get("choice")
            if choice is None:
                continue
            arms = record.get("arms", {})
            if not isinstance(arms, dict):
                arms = {}
            info = arms.get(choice, arms.get(str(choice)))
            if isinstance(info, dict):
                time = as_float(record.get("time", start), start)
                choice_x.append((time - start) / 60.0)
                choice_y.append(posterior_mean(info))

        if choice_x:
            ax.plot(
                choice_x,
                choice_y,
                marker="x",
                linestyle="none",
                color="black",
                alpha=0.7,
                markersize=5,
                label="chosen",
            )

        ax.set_xlabel("Minutes since start")
        ax.set_ylabel("Posterior mean a/(a+b)")
        ax.set_title(f"{tag} {kind} posterior means")
        ax.grid(alpha=0.3)
        handles, labels = ax.get_legend_handles_labels()
        if handles:
            ax.legend(handles, labels, fontsize=7)

    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, f"bandit_{tag}.png"))
    plt.close(fig)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate G2Fuzz presentation figures and coverage CSV.")
    parser.add_argument("--eval", default="results/campaigns", help="Directory containing campaign folders.")
    parser.add_argument("--out", default="results/figures", help="Directory for generated files.")
    args = parser.parse_args(argv)

    campaigns = load_campaigns(args.eval)
    if not campaigns:
        return 0

    try:
        os.makedirs(args.out, exist_ok=True)
    except OSError:
        pass

    write_coverage_csv(campaigns, args.out)

    model_data = build_model_data(campaigns)
    for target in sorted(model_data):
        plot_coverage(
            model_data[target],
            f"Coverage: {target}",
            os.path.join(args.out, f"coverage_{target}.png"),
        )

    final_data = build_final_data(campaigns)
    plot_final_edges(final_data, os.path.join(args.out, "final_edges.png"))

    bandit_candidates = {}
    for camp in campaigns:
        if camp.get("sched") == "bandit" and camp.get("scheduler_path"):
            target = camp["target"]
            current = bandit_candidates.get(target)
            if current is None or camp["rep"] < current["rep"]:
                bandit_candidates[target] = camp

    for tag in sorted(bandit_candidates):
        plot_bandit(tag, bandit_candidates[tag], args.out)

    scheduler_tags = {camp["target"] for camp in campaigns if camp["model"].startswith("sched-")}
    for tag in sorted(scheduler_tags):
        scheduler_campaigns = [
            camp for camp in campaigns if camp["target"] == tag and camp["model"].startswith("sched-")
        ]
        scheduler_data = build_model_data(scheduler_campaigns)
        if scheduler_data.get(tag):
            plot_coverage(
                scheduler_data[tag],
                f"Scheduler: {tag}",
                os.path.join(args.out, f"scheduler_{tag}.png"),
            )

    return 0


if __name__ == "__main__":
    sys.exit(main())
