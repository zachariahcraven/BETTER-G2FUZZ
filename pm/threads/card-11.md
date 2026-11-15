# card-11: scripts/compare: "coverage jumps after LLM steps" measure for A01

## Note nom-nom 2026-11-13 17:57
Files: scripts/compare, docs/ALFRED-ROUNDS.md

## Note nom-nom 2026-11-13 17:57
New section "Coverage after LLM steps" in `scripts/compare`'s report (skipped with `--no-triage`), with `--window MIN` (default 10).

**Method:** for each LLM step that had a seed kept, the step's time is when afl-fuzz imported its first kept seed: queue id N, so the first `plot_data` row whose `corpus_count` is over N (rows every ~5 s). It reports afl-fuzz's `edges` gained in the window before and in the window after, per arm and mutator, and per arm the share of the run's edges that fall in the union of the after-windows next to the share of run time those windows cover.

**Checked on A00** (285 done campaigns, read-only, from a scratch copy on Tempest; 83 s):
- Queue id = corpus count holds in 295 of 300 campaigns; the 5 misses are killed freetype2 runs whose last plot row lags by 1 to 9 entries.
- Hand-computed jhead-r1 continuous gives the same times and gains. File mtimes are NOT usable for this: one import's mtime was 528 s later than its import (afl-fuzz rewrites entries).

**A00 result:**

| arm | campaigns | edges gained in the run | in the 10 min after kept steps | share of run time in those windows |
|---|---|---|---|---|
| control | 61 | 41,724 | 639 (1.5%) | 1.0% |
| continuous | 70 | 54,589 | 13,879 (25.4%) | 14.8% |
| fast-stall | 70 | 55,368 | 3,351 (6.1%) | 5.8% |

Per mutator, "after per step": continuous structure 69.7, feature 47.0, pattern 28.4; fast-stall structure 61.6, feature 38.0, pattern 11.6. Steps with more edges after than before: 44% to 53% in continuous, 53% to 68% in fast-stall.

**How to read it:** it is a correlation, not attribution. In continuous mode steps cluster early, when coverage rises anyway (edges before: 8,929 for feature). Sums are over campaigns, so targets with many edges weigh more. For A01's warm-start arms (all continuous, same start) the arms compare like for like.

**Not done:** no unit test (`scripts/compare` has none); the report's other sections are unchanged (same numbers as before on A00).

## Note nom-nom 2026-11-13 18:00
Review:
##### To check
- Read the A00 table in this card's notes: does before/after per mutator answer what you wanted for A01?
- `git diff scripts/compare`: three new functions (`read_plot`, `edges_at`, `step_coverage`) and one new report block; nothing existing changed.
- On Tempest after pulling: `scripts/compare A00-baseline-6h` (after `scripts/study results`) prints the new section.
##### Changed
`scripts/compare` gains a "Coverage after LLM steps" section: edges gained in the 10 min before and after each LLM step that had a seed kept, per arm and mutator (`--window` sets the minutes). Run on A00's 285 finished campaigns: old and new reports differ only by the added section.

## Note human 2026-11-13 18:03
Approved and committed (75cc6fa).
