# Review record: a0-cov-summary

- Files: experiments/analysis/cov-summary
- Spec: tasks/a0/cov-summary.md
- Author: legacy
- Status (computed from the passes below): PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes)

## Events (in order)

- Pass 1: qwen38, checklist 6-stats -> **findings** (2026-10-15 21:37:28)
  - F1 [low] experiments/analysis/cov-summary:30: The median for an even number of values uses integer floor division (//) instead of true arithmetic mean, so the reported median can be 0.5 lower than the textbook median. The spec says 'medians' without specifying integer rounding.
- Judgement (pass 1, F1): **valid**: Printed per-(target,model) medians floor even-n medians (display only; CSV raw; reported stats come from experiments/analysis/stats). Fix: true median.
- Fix round 1: butler run 20261015-225215-83857 (true median; skipped names reported, explicit -> exit 1); deployed to X
- Pass 2: gemma, checklist 3-data-io -> **clean** (2026-10-15 22:57:10)
- Pass 3: qwen38, checklist 1-spec -> **findings** (2026-10-15 23:01:34)
  - F1 [high] experiments/analysis/cov-summary:89: Access to seeds["files"], seeds["total_edges"], seeds["new_edges"], and queue["total_edges"] (lines 89-93) is outside the try/except block (lines 73-80). A JSON file that has a "seeds" key but is missing any of these sub-fields causes an unhandled KeyError that crashes the entire program, meaning no CSV is written and no file is reported to stderr.
  - F2 [medium] experiments/analysis/cov-summary:130: The spec requires printing a Spearman rank correlation per target over the LLM model campaigns, but the code silently skips any target with fewer than 4 qualifying campaigns (line 130: 'if len(vs) < 4: continue'). For a target with 3 LLM model campaigns, the Spearman is computable but is not printed, contradicting the spec's unconditional 'Prints ... a Spearman rank correlation ... per target'.
  - F3 [low] experiments/analysis/cov-summary:17: The regex on line 17 accepts 'demo' as a valid target, but the spec lists only 'lineup, tiff, png, xml, wad' as valid targets. A file named e.g. 'demo-llama-r1.json' would be parsed and included in the CSV with target 'demo' rather than being reported to stderr as unrecognized.
- Judgement (pass 3, F1): **reject**: A JSON missing sub-fields raises KeyError and the program exits non-zero: a loud failure, not a silent drop (spec forbids silent drops); cov-replay writes complete JSONs.
- Judgement (pass 3, F2): **reject**: Spearman needs >= 4 points to be meaningful; deliberate minimum, not a defect.
- Judgement (pass 3, F3): **reject**: demo was added deliberately by the reviewed wiring change (tasks/e3-wiring.md); this audit spec predates it.
- Pass 4: gemma, checklist 6-stats -> **clean** (2026-10-15 23:23:09)
