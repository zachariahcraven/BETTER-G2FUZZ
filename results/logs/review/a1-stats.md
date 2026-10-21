# Review record: a1-stats

- Files: experiments/analysis/stats
- Spec: tasks/stats.md
- Author: gemma
- Status (computed from the passes below): PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes)

## Events (in order)

- Pass 1: qwen38, checklist 6-stats -> **findings** (2026-10-15 21:39:44)
  - F1 [low] experiments/analysis/stats:167: The check for campaigns present in crashes.csv but missing from cov-results.csv only iterates over crash_sites_data (which excludes campaigns whose rows are all no-repro/hang), so a campaign with only no-repro/hang rows in crashes.csv that is absent from cov-results.csv would not trigger the required error (stderr, exit 2).
- Judgement (pass 1, F1): **valid**: Spec: any campaign present in crashes.csv but missing from cov-results.csv is an error; campaigns with only no-repro/hang rows escape the check.
- Fix round 1: gemma run 20261015-214012-79834: orphan check covers every campaign in crashes.csv (incl. only no-repro/hang rows); full test passes.
- Pass 2: gemma, checklist 5-errors -> **clean** (2026-10-15 22:52:32)
- Pass 3: qwen38, checklist 1-spec -> **clean** (2026-10-15 22:59:04)
- Pass 4: gemma, checklist 6-stats -> **clean** (2026-10-15 22:59:55)
