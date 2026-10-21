#!/usr/bin/env python3
import argparse
import csv
import glob
import json
import os
import sys
from collections import defaultdict

def parse_campaign_name(name):
    # bandit-<tgt>-<arm>-r<N> -> exp: bandit-<tgt>, arm: <arm>
    if name.startswith("bandit-"):
        parts = name.split("-")
        if len(parts) >= 4 and parts[-1].startswith("r"):
            return "-".join(parts[0:2]), "-".join(parts[2:-1])
    
    # Otherwise text before first "-" and the rest up to -r<N>
    if "-" in name:
        first_dash = name.find("-")
        last_dash_r = name.rfind("-r")
        if last_dash_r != -1:
            return name[:first_dash], name[first_dash+1:last_dash_r]
    
    print(f"Unparseable campaign name: {name}", file=sys.stderr)
    sys.exit(2)

def get_target(name):
    if name.startswith("lineup") or "bandit-jhead-" in name: return "jhead"
    if name.startswith("tiff") or "bandit-tiff-" in name: return "tiff_read_rgba_fuzzer"
    if name.startswith("png") or "bandit-png-" in name: return "libpng_read_fuzzer"
    if name.startswith("xml") or "bandit-xml-" in name: return "xml_fuzzer"
    if name.startswith("wad") or "bandit-wad-" in name: return "doom_wad"
    if name.startswith("demo") or "bandit-demo-" in name: return "doom_demo"
    print(f"Unknown target for campaign: {name}", file=sys.stderr)
    sys.exit(2)

def get_campaign_folder(campaign, campaigns_root):
    matches = glob.glob(os.path.join(campaigns_root, "*", campaign))
    if len(matches) != 1:
        print(f"Campaign {campaign} not found uniquely in {campaigns_root}", file=sys.stderr)
        sys.exit(2)
    return matches[0]

def get_execs_done(folder):
    stats_files = glob.glob(os.path.join(folder, "*_output", "default", "fuzzer_stats"))
    if len(stats_files) != 1:
        print(f"Exactly one fuzzer_stats not found in {folder}", file=sys.stderr)
        sys.exit(2)
    
    with open(stats_files[0], "r") as f:
        for line in f:
            if "execs_done" in line and ":" in line:
                try:
                    return int(line.split(":", 1)[1].strip())
                except (ValueError, IndexError):
                    continue
    print(f"execs_done not found in {stats_files[0]}", file=sys.stderr)
    sys.exit(2)

def get_queue_info(folder):
    queue_dir = glob.glob(os.path.join(folder, "*_output", "default", "queue"))
    if len(queue_dir) != 1:
        print(f"Queue folder not found in {folder}", file=sys.stderr)
        sys.exit(2)
    
    q_dir = queue_dir[0]
    files = []
    for entry in os.listdir(q_dir):
        path = os.path.join(q_dir, entry)
        if not os.path.isfile(path) or entry.startswith("."):
            continue
        
        parts = entry.split(",")
        execs_val = None
        for p in parts:
            if p.startswith("execs:"):
                execs_val = int(p.split(":")[1])
                break
        
        if execs_val is None:
            print(f"Queue file {entry} has no execs field", file=sys.stderr)
            sys.exit(2)
        files.append((entry, execs_val))
    return files

def cmd_plan(args):
    cov_path = args.cov or "results/tables/cov-results.csv"
    stats_path = args.stats or "results/tables/stats.csv"
    excl_path = args.exclude or "experiments/inputs/exclusions.csv"
    out_path = args.out or "results/tables/execs-matched-plan.csv"
    
    exclusions = set()
    if os.path.exists(excl_path):
        with open(excl_path, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                exclusions.add(row["campaign"])

    experiments = set()
    with open(stats_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["metric"] == "coverage":
                experiments.add(row["experiment"])
    
    cov_data = {}
    with open(cov_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            cov_data[row["campaign"]] = row

    results = []
    for exp in sorted(experiments):
        exp_campaigns = []
        for camp, data in cov_data.items():
            parsed_exp, _ = parse_campaign_name(camp)
            if parsed_exp == exp and camp not in exclusions:
                exp_campaigns.append(camp)
        
        if not exp_campaigns: continue
        
        campaign_stats = {}
        for camp in exp_campaigns:
            folder = get_campaign_folder(camp, args.campaigns)
            done = get_execs_done(folder)
            q_files = get_queue_info(folder)
            campaign_stats[camp] = (done, len(q_files), q_files)
        
        cutoff = min(s[0] for s in campaign_stats.values())
        
        for camp in sorted(exp_campaigns):
            done, total_q, q_list = campaign_stats[camp]
            at_cutoff = sum(1 for _, ex in q_list if ex <= cutoff)
            _, arm = parse_campaign_name(camp)
            results.append({
                "experiment": exp,
                "campaign": camp,
                "arm": arm,
                "target": get_target(camp),
                "execs_done": done,
                "cutoff": cutoff,
                "queue_files": total_q,
                "files_at_cutoff": at_cutoff
            })

    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["experiment", "campaign", "arm", "target", "execs_done", "cutoff", "queue_files", "files_at_cutoff"])
        writer.writeheader()
        writer.writerows(results)

def cmd_select(args):
    cutoff = int(args.cutoff)
    if os.path.exists(args.dir):
        print(f"Directory {args.dir} already exists", file=sys.stderr)
        sys.exit(2)
    
    os.makedirs(args.dir)
    folder = get_campaign_folder(args.campaign, args.campaigns)
    q_files = get_queue_info(folder)
    
    count = 0
    queue_dir = glob.glob(os.path.join(folder, "*_output", "default", "queue"))[0]
    for name, execs in q_files:
        if execs <= cutoff:
            os.symlink(os.path.abspath(os.path.join(queue_dir, name)), os.path.join(args.dir, name))
            count += 1
    print(count)

def cmd_table(args):
    plan_path = args.plan or "results/tables/execs-matched-plan.csv"
    replays_dir = args.replays or "results/cov-execs"
    cov_path = args.cov or "results/tables/cov-results.csv"
    out_path = args.out or "results/tables/execs-matched.csv"
    cov_out_path = args.cov_out or "results/tables/execs-matched-cov.csv"
    
    cov_data = {}
    with open(cov_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            cov_data[row["campaign"]] = row

    plan_rows = []
    with open(plan_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            plan_rows.append(row)

    final_rows = []
    exp_summary = defaultdict(lambda: {"cutoff": 0, "count": 0})
    
    for row in plan_rows:
        camp = row["campaign"]
        if camp not in cov_data:
            print(f"Campaign {camp} from plan not found in cov CSV", file=sys.stderr)
            sys.exit(2)
        replay_file = os.path.join(replays_dir, f"{camp}.json")
        try:
            with open(replay_file, "r") as f:
                replay_data = json.load(f)
                edges_at_cutoff = replay_data["total_edges"]
        except Exception:
            print(f"Missing or unparseable replay file: {replay_file}", file=sys.stderr)
            sys.exit(2)
        
        row["edges_at_cutoff"] = edges_at_cutoff
        row["queue_edges"] = cov_data[camp]["queue_edges"]
        final_rows.append(row)
        
        exp = row["experiment"]
        exp_summary[exp]["cutoff"] = int(row["cutoff"])
        exp_summary[exp]["count"] += 1

    with open(out_path, "w", newline="") as f:
        cols = ["experiment", "campaign", "arm", "execs_done", "cutoff", "files_at_cutoff", "edges_at_cutoff", "queue_edges"]
        writer = csv.DictWriter(f, fieldnames=cols)
        writer.writeheader()
        for row in final_rows:
            writer.writerow({k: row[k] for k in cols})
        
    with open(cov_out_path, "w", newline="") as f:
        # Exact column layout of cov-results.csv
        cols = ["campaign", "target", "model", "rep", "seed_files", "seed_edges", "new_edges", "generators", "queue_edges"]
        writer = csv.DictWriter(f, fieldnames=cols)
        writer.writeheader()
        for i, row in enumerate(plan_rows):
            camp = row["campaign"]
            c_row = cov_data[camp].copy()
            c_row["queue_edges"] = final_rows[i]["edges_at_cutoff"]
            writer.writerow({k: c_row[k] for k in cols})

    for exp in sorted(exp_summary.keys()):
        s = exp_summary[exp]
        print(f"{exp}: cutoff {s['cutoff']}, campaigns {s['count']}")

def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command")
    
    p_parser = subparsers.add_parser("plan")
    p_parser.add_argument("--campaigns", default="results/campaigns")
    p_parser.add_argument("--cov")
    p_parser.add_argument("--stats")
    p_parser.add_argument("--exclude")
    p_parser.add_argument("--out")
    
    s_parser = subparsers.add_parser("select")
    s_parser.add_argument("--campaigns", default="results/campaigns")
    s_parser.add_argument("campaign")
    s_parser.add_argument("cutoff")
    s_parser.add_argument("dir")
    
    t_parser = subparsers.add_parser("table")
    t_parser.add_argument("--campaigns", default="results/campaigns")
    t_parser.add_argument("--plan")
    t_parser.add_argument("--replays")
    t_parser.add_argument("--cov")
    t_parser.add_argument("--out")
    t_parser.add_argument("--cov-out")
    
    args = parser.parse_args()
    if args.command == "plan": cmd_plan(args)
    elif args.command == "select": cmd_select(args)
    elif args.command == "table": cmd_table(args)
    else: parser.print_help()

if __name__ == "__main__":
    main()
