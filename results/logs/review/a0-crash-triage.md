# Review record: a0-crash-triage

- Files: experiments/analysis/lib/crash_triage.py, experiments/analysis/crash-triage
- Spec: tasks/a0/crash-triage.md
- Author: legacy
- Status (computed from the passes below): PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes)

## Events (in order)

- Pass 1: gemma, checklist 3-data-io -> **clean** (2026-10-15 21:35:31)
- Pass 2: qwen38, checklist 5-errors -> **findings** (2026-10-15 21:40:40)
  - F1 [medium] experiments/analysis/lib/crash_triage.py:78: Non-matching campaign names are silently skipped (line 78 `else: continue`) with no warning, no error, and no non-zero exit. When every user-supplied name is skipped the script writes a header-only CSV, prints 'per-crash rows: results/tables/crashes.csv', and exits 0 — a failure that looks identical to a run with zero crashes.
- Judgement (pass 2, F1): **valid**: Unrecognized campaign names (explicit or globbed) are skipped silently. Fix: report each skipped name on stderr; exit 1 if an explicitly named campaign is skipped.
- Fix round 1: butler run 20261015-225215-83857 (true median; skipped names reported, explicit -> exit 1); deployed to X
- Pass 3: gemma, checklist 1-spec -> **clean** (2026-10-15 22:57:13)
- Pass 4: qwen38, checklist 6-stats -> **clean** (2026-10-15 22:59:07)
- Pass 5: gemma, checklist 5-errors -> **findings** (2026-10-15 23:00:23)
  - F1 [medium] experiments/analysis/lib/crash_triage.py:123: The script can produce a 'complete-looking' CSV file even if some target binaries were missing or failed to execute, as it doesn't track execution failures for non-explicitly requested campaigns.
- Judgement (pass 5, F1): **reject**: Skipped names are reported on stderr since fix round 1; a missing ASan binary raises FileNotFoundError and the script exits non-zero before writing the CSV (loud, not complete-looking).
