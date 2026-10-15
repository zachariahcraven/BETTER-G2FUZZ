#!/usr/bin/env python3
"""Presentation figures for Doom fuzzing runs."""
import argparse
import csv
import json
import os
import subprocess
import sys
import tempfile

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image, ImageDraw, ImageFont

WAD_MAP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wad_map.py")


def parse_args():
    p = argparse.ArgumentParser(description="Doom fuzzing demo figures")
    p.add_argument("--eval", default="results/campaigns")
    p.add_argument("--crashes", default="results/tables/crashes.csv")
    p.add_argument("--stock", default="targets/doom/seeds")
    p.add_argument("--out", default="results/figures")
    p.add_argument("--max", type=int, default=12)
    return p.parse_args()


def wad_list_maps(wad_path):
    """Return list of map names from a WAD file, or empty list on failure."""
    try:
        r = subprocess.run(
            [sys.executable, WAD_MAP, wad_path, "--list"],
            capture_output=True, text=True, timeout=30
        )
        if r.returncode != 0:
            return []
        return [line.strip() for line in r.stdout.strip().splitlines() if line.strip()]
    except Exception:
        return []


def wad_draw(wad_path, map_name, out_png, size=400):
    """Draw a single map to out_png. Returns True on success."""
    try:
        r = subprocess.run(
            [sys.executable, WAD_MAP, wad_path, map_name, "-o", out_png,
             "--size", str(size)],
            capture_output=True, text=True, timeout=60
        )
        return r.returncode == 0
    except Exception:
        return False


def first_map_renders(wad_path, size=400):
    """Return (map_name, True) if first listed map renders, else (None, False)."""
    maps = wad_list_maps(wad_path)
    if not maps:
        return None, False
    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        ok = wad_draw(wad_path, maps[0], tmp_path, size)
        return maps[0], ok
    except Exception:
        return None, False
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)


def load_stock(stock_dir):
    """Load stock WAD files as (name, bytes) pairs, sorted by name."""
    try:
        entries = os.listdir(stock_dir)
    except Exception:
        return []
    blobs = []
    for name in sorted(entries):
        path = os.path.join(stock_dir, name)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "rb") as fh:
                blobs.append((name, fh.read()))
        except Exception:
            pass
    return blobs


def bytes_changed(crash_file, stock):
    """Smallest number of differing bytes vs any same-length stock file, plus its name.

    Returns (count, name); (None, None) if no stock file has the crash file's length.
    """
    try:
        with open(crash_file, "rb") as fh:
            data = fh.read()
    except Exception:
        return None, None
    n = len(data)
    best = None
    best_name = None
    for name, blob in stock:
        if len(blob) != n:
            continue
        d = sum(a != b for a, b in zip(data, blob))
        if best is None or d < best:
            best = d
            best_name = name
    return best, best_name


def _campaign_map(campaigns_dir):
    """Map campaign basename -> full path, skipping archive."""
    m = {}
    try:
        groups = os.listdir(campaigns_dir)
    except OSError:
        return m
    for group in groups:
        if group == "archive":
            continue
        group_path = os.path.join(campaigns_dir, group)
        if not os.path.isdir(group_path):
            continue
        for name in os.listdir(group_path):
            path = os.path.join(group_path, name)
            if os.path.isdir(path):
                m[name] = path
    return m


def load_crash_sites(eval_dir, crashes_csv, max_sites, stock):
    """Load crash sites, choose the best crash file per site, order for variety.

    Returns (sites, all_wad_models): sites is an ordered list of dicts; all_wad_models
    is the set of every non-sched wad model seen in the CSV.
    """
    try:
        with open(crashes_csv, newline="") as f:
            rows = list(csv.DictReader(f))
    except Exception:
        return [], set()

    wad_rows = [row for row in rows if row.get("target") == "wad" and row.get("kind") not in ("no-repro", "hang")]
    if not wad_rows:
        return [], set()

    all_wad_models = set()
    sites = {}
    for row in wad_rows:
        kind = row.get("kind", "")
        frames = row.get("frames", "")
        frame = frames.split(" | ")[0]
        key = (kind, frame)
        site = sites.setdefault(key, {"models": set(), "rows": []})
        site["rows"].append(row)
        model = row.get("model", "")
        if not model.startswith("sched-"):
            site["models"].add(model)
            all_wad_models.add(model)

    # For each site choose its crash file: among files whose first map renders,
    # the smallest bytes_changed (None counts as largest); ties keep CSV order.
    camp_map = _campaign_map(eval_dir)
    candidates = []
    for (kind, frame), site in sites.items():
        chosen = None  # (bytes_changed, file, map, stock_name)
        for row in site["rows"]:
            camp_path = camp_map.get(row["campaign"])
            if camp_path is None:
                continue
            crash_file = os.path.join(
                camp_path, "doom_wad_output", "default", "crashes", row["crash"]
            )
            if not os.path.isfile(crash_file):
                continue
            map_name, ok = first_map_renders(crash_file)
            if not ok:
                continue
            bc, bc_name = bytes_changed(crash_file, stock)
            if chosen is None:
                chosen = (bc, crash_file, map_name, bc_name)
                continue
            prev = chosen[0]
            if bc is None:
                continue  # None counts as largest
            if prev is None or bc < prev:
                chosen = (bc, crash_file, map_name, bc_name)
        if chosen is None:
            continue
        bc, crash_file, map_name, bc_name = chosen
        real_models = site["models"]
        candidates.append({
            "kind": kind,
            "frame": frame,
            "file": crash_file,
            "map": map_name,
            "bytes_changed": bc,
            "stock_name": bc_name,
            "models": sorted(real_models) if real_models else ["sched"],
            "model_count": len(real_models),
        })

    # Order: LLM-only sites first (no baseline), then baseline-found sites.
    # Within each group: variety first (one per kind), then rest by model count.
    llm_only = [c for c in candidates if "baseline" not in c["models"]]
    baseline_found = [c for c in candidates if "baseline" in c["models"]]

    def order_group(group):
        by_kind = {}
        for c in group:
            cur = by_kind.get(c["kind"])
            if cur is None:
                by_kind[c["kind"]] = c
            elif c["model_count"] > cur["model_count"]:
                by_kind[c["kind"]] = c
            elif c["model_count"] == cur["model_count"] and c["frame"] < cur["frame"]:
                by_kind[c["kind"]] = c
        reps = sorted(by_kind.values(), key=lambda c: (-c["model_count"], c["kind"], c["frame"]))
        rep_ids = {id(c) for c in reps}
        rest = sorted(
            [c for c in group if id(c) not in rep_ids],
            key=lambda c: (-c["model_count"], c["kind"], c["frame"]),
        )
        return reps + rest

    return (order_group(llm_only) + order_group(baseline_found))[:max_sites], all_wad_models


def wrap_text(draw, text, font, max_width):
    """Wrap text at word boundaries to fit within max_width pixels."""
    words = text.split()
    lines = []
    current = ""
    for word in words:
        test = (current + " " + word).strip()
        if draw.textlength(test, font=font) <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_crash_maps(sites, out_dir, all_wad_models):
    """Render crash_maps.png (tile grid) and crash_maps.json."""
    os.makedirs(out_dir, exist_ok=True)

    # JSON
    json_sites = []
    for s in sites:
        title = "%s (no stack trace)" % s["kind"] if not s["frame"] else "%s in %s" % (s["kind"], s["frame"])
        if all_wad_models and set(s["models"]) == all_wad_models:
            found_by = "found by: all %d models" % (len(all_wad_models - {"baseline"}))
            if "baseline" in all_wad_models:
                found_by += " + baseline"
        else:
            found_by = "found by: " + ", ".join(s["models"])
        if "baseline" not in s["models"]:
            found_by += " (LLM runs only)"
        json_sites.append({
            "kind": s["kind"],
            "frame": s["frame"],
            "file": s["file"],
            "map": s["map"],
            "bytes_changed": s["bytes_changed"],
            "models": s["models"],
            "title": title,
            "found_by": found_by,
        })
    with open(os.path.join(out_dir, "crash_maps.json"), "w") as f:
        json.dump(json_sites, f, indent=2)

    n = len(sites)
    cols = 3
    nrows = (n + cols - 1) // cols
    cell_w = 400
    cell_h = 560  # 400 px map + 160 px caption area
    width = cols * cell_w
    height = nrows * cell_h

    img = Image.new("RGB", (width, height), (25, 25, 35))
    draw = ImageDraw.Draw(img)
    font = ImageFont.load_default(size=18)

    for i, site in enumerate(sites):
        col = i % cols
        row = i // cols
        x0 = col * cell_w
        y0 = row * cell_h

        # Render and paste the map
        tmp_path = None
        try:
            fd, tmp_path = tempfile.mkstemp(suffix=".png")
            os.close(fd)
            if wad_draw(site["file"], site["map"], tmp_path, 400):
                map_img = Image.open(tmp_path).convert("RGB")
                mw, mh = map_img.size
                img.paste(map_img, (x0 + (cell_w - mw) // 2, y0 + (400 - mh) // 2))
        except Exception:
            pass
        finally:
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)

        # Captions
        c1 = "%s (no stack trace)" % site["kind"] if not site["frame"] else "%s in %s" % (site["kind"], site["frame"])
        if all_wad_models and set(site["models"]) == all_wad_models:
            c2 = "found by: all %d models" % (len(all_wad_models - {"baseline"}))
            if "baseline" in all_wad_models:
                c2 += " + baseline"
        else:
            c2 = "found by: " + ", ".join(site["models"])
        if "baseline" not in site["models"]:
            c2 += " (LLM runs only)"
        if site["bytes_changed"] is None:
            c3 = "not a modified stock map"
        else:
            c3 = "%s bytes changed from %s" % (site["bytes_changed"], site["stock_name"])
        max_w = cell_w - 12
        y = y0 + 405
        for line in wrap_text(draw, c1, font, max_w)[:2]:
            draw.text((x0 + 6, y), line, fill=(220, 220, 220), font=font)
            y += 22
        for line in wrap_text(draw, c2, font, max_w):
            draw.text((x0 + 6, y), line, fill=(160, 160, 180), font=font)
            y += 22
        for line in wrap_text(draw, c3, font, max_w):
            draw.text((x0 + 6, y), line, fill=(255, 190, 90), font=font)
            y += 22

    img.save(os.path.join(out_dir, "crash_maps.png"))


def analyze_wad_validity(eval_dir, out_dir):
    """Analyze generated WAD seeds per model; write wad_validity.csv and .png."""
    try:
        groups = os.listdir(eval_dir)
    except Exception:
        return

    # Discover campaigns: wad-<model>-r<N>
    campaigns = {}  # model -> [full paths]
    for group in sorted(groups):
        if group == "archive":
            continue
        group_path = os.path.join(eval_dir, group)
        if not os.path.isdir(group_path):
            continue
        try:
            entries = os.listdir(group_path)
        except OSError:
            continue
        for e in entries:
            if not e.startswith("wad-"):
                continue
            full = os.path.join(group_path, e)
            if not os.path.isdir(full):
                continue
            rest = e[4:]  # strip "wad-"
            if "-r" not in rest:
                continue
            model = rest.rsplit("-r", 1)[0]
            if model == "baseline":
                continue
            campaigns.setdefault(model, []).append(full)

    if not campaigns:
        return

    results = []
    for model in sorted(campaigns):
        total_seeds = 0
        total_magic = 0
        total_renders = 0
        for camp in campaigns[model]:
            seeds_dir = os.path.join(camp, "initial_seeds")
            if not os.path.isdir(seeds_dir):
                continue
            for fname in sorted(os.listdir(seeds_dir)):
                if fname.startswith("freedoom2-"):
                    continue
                fpath = os.path.join(seeds_dir, fname)
                if not os.path.isfile(fpath):
                    continue
                total_seeds += 1
                # Magic bytes
                try:
                    with open(fpath, "rb") as fh:
                        hdr = fh.read(4)
                    if hdr in (b"IWAD", b"PWAD"):
                        total_magic += 1
                except Exception:
                    pass
                # Render check (small size for speed)
                _, ok = first_map_renders(fpath, size=100)
                if ok:
                    total_renders += 1
        results.append((model, total_seeds, total_magic, total_renders))

    if not results:
        return

    os.makedirs(out_dir, exist_ok=True)

    # CSV
    with open(os.path.join(out_dir, "wad_validity.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["model", "seeds", "magic", "renders"])
        for model, seeds, magic, renders in results:
            w.writerow([model, seeds, magic, renders])

    # Bar chart
    models = [r[0] for r in results]
    magic_pct = [100.0 * r[2] / r[1] if r[1] else 0.0 for r in results]
    renders_pct = [100.0 * r[3] / r[1] if r[1] else 0.0 for r in results]

    fig, ax = plt.subplots(figsize=(max(8, 2.5 * len(models)), 5))
    x = list(range(len(models)))
    bw = 0.35

    ax.bar([i - bw / 2 for i in x], magic_pct, bw, label="IWAD/PWAD", color="#4a90d9")
    ax.bar([i + bw / 2 for i in x], renders_pct, bw, label="Renders", color="#7ed321")

    ax.set_xlabel("Model")
    ax.set_ylabel("Percentage (%)")
    ax.set_title("WAD Seed Validity by Model")
    ax.set_xticks(x)
    ax.set_xticklabels([f"{m}\n(n={r[1]})" for m, r in zip(models, results)])
    ax.set_ylim(0, 110)
    ax.legend()

    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, "wad_validity.png"), dpi=100)
    plt.close(fig)


def main():
    args = parse_args()
    try:
        stock = load_stock(args.stock)
        # Figure 1: crash maps
        sites, all_wad_models = load_crash_sites(args.eval, args.crashes, args.max, stock)
        if sites:
            draw_crash_maps(sites, args.out, all_wad_models)

        # Figure 2: wad validity
        analyze_wad_validity(args.eval, args.out)
    except Exception:
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
