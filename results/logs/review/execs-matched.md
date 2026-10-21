# Review record: execs-matched

- Files: experiments/analysis/lib/execs_matched.py, experiments/runners/execs-replay.sbatch (Claude glue)
- Spec: tasks/execs-matched.md
- Author: gemma-4-31B-it (N-version: Claude reference)
- Status (computed from the passes below): PASSED (driver rule: clean streak 4 since the last fix, families gemma, qwen, non-author yes)
- Manager's note: PASSED: clean qwen38 data-io/stats/spec + gemma errors (one qwen38 spec pass failed on format and was rerun). Real data: plan and both tables byte-identical to Claude's reference. Validation: the campaign that sets each experiment's cutoff reproduces its published queue_edges exactly (non-Doom) or within -3..+6 edges (Doom replay nondeterminism).

## Events (in order)

- Judgement (pass 0, C1): **valid**: Claude's read: select made symlinks relative to the campaigns path given (default relative) -> broken links. Test added (relative --campaigns), fails on gemma, passes on reference.
- Fix round 1: butler fix: os.path.abspath for link targets
- Pass 1: qwen38, checklist 3-data-io -> **clean** (2026-10-16 11:01:38)
- Pass 2: qwen38, checklist 6-stats -> **clean** (2026-10-16 11:00:41)
- Pass 3: gemma, checklist 5-errors -> **clean** (2026-10-16 10:59:46)
- Pass 4: qwen38, checklist 1-spec -> **failed** (2026-10-16 11:05:01)
  - problem: missing 'examined' or 'findings' list
- Pass 5: qwen38, checklist 1-spec -> **clean** (2026-10-16 11:09:42)
