#!/usr/bin/env python3
"""Measure code coverage of seed files for a fuzz target."""

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Measure code coverage of seed files for a fuzz target."
    )
    parser.add_argument("target", help="AFL-instrumented binary")
    parser.add_argument("seed_dir", help="Folder of seed files")
    parser.add_argument("--stock", help="Folder of stock seeds")
    parser.add_argument("--args", default="@@",
                        help="Target command-line arguments, with one '@@' for the input file")
    parser.add_argument("-t", "--timeout", type=int, default=1000,
                        help="Per-input timeout in ms (default: 1000)")
    return parser.parse_args()


def get_generator(filename):
    """Extract generator name from filename. Stock seeds have no underscore pattern."""
    basename = os.path.basename(filename)
    if "_" in basename:
        parts = basename.split("_")
        if len(parts) >= 2:
            # Check if last part before extension is a number
            ext_part = parts[-1]
            dot_idx = ext_part.find(".")
            if dot_idx != -1:
                num_part = ext_part[:dot_idx]
            else:
                num_part = ext_part
            if num_part.isdigit():
                return "_".join(parts[:-1])
    return "stock"


def target_argv(args):
    """Split target arguments and check that exactly one '@@' marks the input file."""
    argv = shlex.split(args)
    if argv.count("@@") != 1:
        raise ValueError("--args must contain exactly one '@@'")
    return argv


def run_afl_showmap(target, input_dir, output_dir, timeout_ms, args="@@"):
    """Run afl-showmap once per input, writing <output_dir>/<input name>.

    Not its folder mode (-i): that runs the target persistently, so one-time setup edges land only
    in the first input's map and skew the per-generator numbers. A crashing or hanging input still
    writes the edges it reached, so afl-showmap's exit status is not an error here.
    """
    timeouts = []
    argv = target_argv(args)
    for name in sorted(os.listdir(input_dir)):
        path = os.path.join(input_dir, name)
        if not os.path.isfile(path):
            continue
        work_dir = tempfile.mkdtemp()
        try:
            copy_path = os.path.join(work_dir, name)
            shutil.copyfile(path, copy_path)
            cmd = ["afl-showmap", "-q", "-o", os.path.abspath(os.path.join(output_dir, name)),
                   "-t", str(timeout_ms),
                   "--", os.path.abspath(target),
                   *[copy_path if arg == "@@" else arg for arg in argv]]
            try:
                subprocess.run(cmd, capture_output=True, timeout=timeout_ms / 1000.0 + 30,
                               cwd=work_dir)
            except FileNotFoundError:
                raise RuntimeError("afl-showmap not found on PATH")
            except subprocess.TimeoutExpired:
                timeouts.append(name)
        finally:
            shutil.rmtree(work_dir, ignore_errors=True)
    return timeouts


def parse_map_file(map_path):
    """Parse an afl-showmap map file and return set of edge IDs.

    Raises ValueError if any non-empty line is not of the form '<edge id>:<count>'.
    """
    edges = set()
    with open(map_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(":")
            if len(parts) != 2 or not parts[0].isdigit() or not parts[1].isdigit():
                raise ValueError(f"unparseable line: {line!r}")
            edges.add(int(parts[0]))
    return edges


def main():
    args = parse_args()

    try:
        # Validate inputs
        target_argv(args.args)
        if not os.path.isfile(args.target):
            raise FileNotFoundError(f"Target not found: {args.target}")

        if not os.access(args.target, os.X_OK):
            raise PermissionError(f"Target not executable: {args.target}")

        if not os.path.isdir(args.seed_dir):
            raise FileNotFoundError(f"Seed directory not found: {args.seed_dir}")

        seed_files = [f for f in os.listdir(args.seed_dir)
                      if os.path.isfile(os.path.join(args.seed_dir, f))]
        if not seed_files:
            raise ValueError("Seed directory is empty")

        # Create temp directory
        temp_dir = tempfile.mkdtemp()

        try:
            # Run afl-showmap on seed directory
            seed_map_dir = os.path.join(temp_dir, "seed_maps")
            os.makedirs(seed_map_dir)
            seed_timeouts = run_afl_showmap(args.target, args.seed_dir, seed_map_dir, args.timeout,
                                            args.args)
            failures = [(n, "timeout") for n in seed_timeouts]

            # Collect edges from each seed file
            seed_edges = {}
            for seed_file in seed_files:
                map_path = os.path.join(seed_map_dir, seed_file)
                if not os.path.exists(map_path):
                    failures.append((seed_file, "no map file produced"))
                    continue
                try:
                    seed_edges[seed_file] = parse_map_file(map_path)
                except ValueError as e:
                    failures.append((seed_file, str(e)))

            # Calculate total edges
            all_edges = set()
            for edges in seed_edges.values():
                all_edges.update(edges)
            total_edges = len(all_edges)

            # Handle stock seeds if provided
            stock_edges = None
            new_edges = None

            if args.stock:
                if not os.path.isdir(args.stock):
                    raise FileNotFoundError(f"Stock directory not found: {args.stock}")

                stock_seed_files = [f for f in os.listdir(args.stock)
                                    if os.path.isfile(os.path.join(args.stock, f))]
                if not stock_seed_files:
                    raise ValueError("Stock directory is empty")

                stock_map_dir = os.path.join(temp_dir, "stock_maps")
                os.makedirs(stock_map_dir)
                stock_timeouts = run_afl_showmap(args.target, args.stock, stock_map_dir, args.timeout,
                                                 args.args)
                failures.extend([(n, "timeout") for n in stock_timeouts])

                stock_edges_set = set()
                for seed_file in stock_seed_files:
                    map_path = os.path.join(stock_map_dir, seed_file)
                    if not os.path.exists(map_path):
                        failures.append((seed_file, "no map file produced"))
                        continue
                    try:
                        stock_edges_set.update(parse_map_file(map_path))
                    except ValueError as e:
                        failures.append((seed_file, str(e)))

                stock_edges = len(stock_edges_set)
                new_edges = total_edges - stock_edges

            if failures:
                for name, reason in failures:
                    print(f"seed_cov: {name}: {reason}", file=sys.stderr)
                sys.exit(2)

            # Group by generator
            generators = {}
            for seed_file, edges in seed_edges.items():
                gen = get_generator(seed_file)
                if gen not in generators:
                    generators[gen] = {"edges": set(), "files": 0}
                generators[gen]["edges"].update(edges)
                generators[gen]["files"] += 1

            # Calculate per-generator stats
            per_generator = {}
            for gen, data in generators.items():
                gen_edges = data["edges"]
                gen_edge_count = len(gen_edges)

                # Unique edges: edges not reachable by any other generator
                other_edges = set()
                for other_gen, other_data in generators.items():
                    if other_gen != gen:
                        other_edges.update(other_data["edges"])

                unique_edges = len(gen_edges - other_edges)

                per_generator[gen] = {
                    "files": data["files"],
                    "edges": gen_edge_count,
                    "unique": unique_edges
                }

            # Build output
            output = {
                "target": args.target,
                "files": len(seed_files),
                "total_edges": total_edges,
                "stock_edges": stock_edges,
                "new_edges": new_edges,
                "per_generator": per_generator
            }

            print(json.dumps(output, indent=1))

        finally:
            # Cleanup temp directory
            shutil.rmtree(temp_dir, ignore_errors=True)

    except Exception as e:
        print(f"seed_cov: error: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
