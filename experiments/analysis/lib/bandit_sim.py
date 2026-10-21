#!/usr/bin/env python3
"""bandit_sim.py: is a bandit-vs-random tie expected at the observed budget? (see the task spec)"""
import argparse
import csv
import os
import random
import statistics
import sys
from collections import namedtuple

try:
    sys.path.append(os.path.join(os.path.dirname(__file__), "../../../"))
    from g2fuzz.py_utils.scheduler import credit
except ImportError:
    # Fallback for different environment structures if necessary, 
    # though the prompt specifies the relative path.
    import sys
    sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../")))
    from g2fuzz.py_utils.scheduler import credit

Arm = namedtuple("Arm", ["name", "p"])

def simulate(pool_name, arms, budget, policy, seed_val, reps):
    rng = random.Random(f"{seed_val}-{pool_name}-{budget}-{policy}")
    results = []

    for _ in range(reps):
        successes = 0
        # State for Thompson Sampling
        # alpha = 1 + successes, beta = 1 + failures
        counts = {arm.name: [0, 0] for arm in arms} # [successes, failures]
        
        for _ in range(budget):
            chosen_arm = None
            if policy == "random":
                chosen_arm = rng.choice(arms)
            elif policy == "oracle":
                # Max p, ties: first in name order (arms is already sorted)
                best_p = -1.0
                for arm in arms:
                    if arm.p > best_p:
                        best_p = arm.p
                        chosen_arm = arm
            elif policy == "thompson":
                best_sample = -1.0
                for arm in arms:
                    s, f = counts[arm.name]
                    sample = rng.betavariate(1 + s, 1 + f)
                    if sample > best_sample:
                        best_sample = sample
                        chosen_arm = arm
            
            # Simulate outcome
            if rng.random() < chosen_arm.p:
                successes += 1
                counts[chosen_arm.name][0] += 1
            else:
                counts[chosen_arm.name][1] += 1
        
        results.append(successes / budget)
    
    return results

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pool", action="append", required=True)
    parser.add_argument("--budgets", nargs="+", default=["5", "20", "50", "200", "2000"])
    parser.add_argument("--reps", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=591)
    parser.add_argument("--out", default="results/tables/bandit-sim.csv")
    args = parser.parse_args()

    budgets = [int(b) for b in args.budgets]
    
    # Process pools
    all_data = []
    for out_dir in args.pool:
        # Pool name is two levels above OUT_DIR
        # OUT_DIR: <campaign>/<target>_output/default
        # Path: .../campaign/target_output/default
        parts = os.path.normpath(out_dir).split(os.sep)
        if len(parts) < 3:
            # This case shouldn't happen based on spec but for safety:
            pool_name = "unknown"
        else:
            pool_name = parts[-3]

        try:
            credits = credit(out_dir)
        except Exception:
            print(f"Error accessing {out_dir}", file=sys.stderr)
            sys.exit(2)

        # Arms: generators with seeds >= 1
        arm_list = []
        for gen, data in credits.items():
            seeds = data.get("seeds", 0)
            if seeds >= 1:
                p = data.get("productive", 0) / seeds
                arm_list.append(Arm(gen, p))
        
        if not arm_list:
            print(f"No arms found in {out_dir}", file=sys.stderr)
            sys.exit(2)
        
        arm_list.sort(key=lambda x: x.name)
        num_arms = len(arm_list)

        for T in budgets:
            policy_results = {}
            for pol in ["random", "thompson", "oracle"]:
                res = simulate(pool_name, arm_list, T, pol, args.seed, args.reps)
                policy_results[pol] = {
                    "mean": statistics.mean(res),
                    "sd": statistics.pstdev(res)
                }
            
            rand_mean = policy_results["random"]["mean"]
            for pol in ["random", "thompson", "oracle"]:
                m = policy_results[pol]["mean"]
                s = policy_results[pol]["sd"]
                ratio = "%.6g" % (m / rand_mean) if rand_mean != 0 else ""
                all_data.append({
                    "pool": pool_name,
                    "arms": str(num_arms),
                    "budget": str(T),
                    "policy": pol,
                    "mean_rate": "%.6g" % m,
                    "sd_rate": "%.6g" % s,
                    "ratio_to_random": ratio
                })

    # Write CSV
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["pool", "arms", "budget", "policy", "mean_rate", "sd_rate", "ratio_to_random"])
        writer.writeheader()
        writer.writerows(all_data)

if __name__ == "__main__":
    main()
