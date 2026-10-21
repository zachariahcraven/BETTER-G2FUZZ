# Review record: b2-budget

- Files: experiments/analysis/bandit-budget
- Spec: tasks/bandit-budget.md
- Author: gemma
- Status (computed from the passes below): PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes)

## Events (in order)

- Pass 1: qwen38, checklist 1-spec -> **findings** (2026-10-15 23:36:30)
  - F1 [low] experiments/analysis/bandit-budget:18: The spec mandates importing credit() via 'sys.path insert of that folder', but the code uses importlib.util.spec_from_file_location instead. If scheduler.py performs relative or package-internal imports, the importlib path may fail to resolve them (since the module's __package__ is not set), whereas sys.path.insert would allow those imports to succeed. In the failure case the code prints an error and skips the campaign rather than producing a wrong value, so numerical results are not corrupted, but the mechanism deviates from the spec.
- Judgement (pass 1, F1): **valid**: The import mechanism itself is harmless, but on failure the tool prints an error and s: the campaign is silently missing from the table and the run exits 0 (partial result that looks complete). Fix: import credit() once at start via sys.path insert (spec), exit 2 if that fails.
- Fix round 1: gemma run 20261016-002251-85721: credit imported once via sys.path, exit 2 on failure, no silent campaign skip; test passes; real-data output == reference
- Pass 2: gemma, checklist 6-stats -> **clean** (2026-10-16 00:29:31)
- Pass 3: qwen38, checklist 2-edges -> **clean** (2026-10-16 00:31:51)
- Pass 4: gemma, checklist 3-data-io -> **clean** (2026-10-16 00:32:24)
