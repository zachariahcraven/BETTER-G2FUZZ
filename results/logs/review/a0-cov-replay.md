# Review record: a0-cov-replay

- Files: experiments/runners/cov-replay.sbatch, experiments/analysis/lib/seed_cov.py
- Spec: tasks/a0/cov-replay.md
- Author: legacy
- Status (computed from the passes below): PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes)

## Events (in order)

- Pass 1: qwen38, checklist 6-stats -> **clean** (2026-10-15 17:55:14)
- Pass 2: gemma, checklist 3-data-io -> **failed** (2026-10-15 17:56:50)
  - problem: reply is not a JSON object
- Pass 3: qwen38, checklist 5-errors -> **failed** (2026-10-15 18:06:22)
  - problem: reply is not a JSON object
- Pass 4: gemma, checklist 6-stats -> **findings** (2026-10-15 18:08:01)
  - F1 [high] experiments/analysis/lib/seed_cov.py:144: The calculation of 'new_edges' is wrong because it subtracts the count of stock edges from the total count, rather than calculating the size of the set difference. This is only correct if stock_edges is a strict subset of total_edges, but the spec allows stock seeds to be provided via --stock independently of the seed_dir.
- Judgement (pass 4, F1): **reject**: Spec defines new_edges = total_edges - stock_edges because initial_seeds always contain the stock files (scripts/fuzz copies $SEEDS/* into initial_seeds; ctl seed sets also contain the stock files); same false positive as gemma calibration.
- Pass 5: qwen38, checklist 7-parity -> **clean** (2026-10-15 18:11:46)
