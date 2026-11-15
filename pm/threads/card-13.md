# card-13: New stall mutator "uncovered": show the LLM source of target functions the queue has not reached (A03 arm)

## Note nom-nom 2026-11-14 19:37
**Why this card (evidence from A00/A02).** The stall mutators (feature, structure, pattern) mutate generators blind: 0.04-0.10 kept seeds per LLM step, in-run LLM seeds' descendants at most 1.8% of the queue, and no coverage gain for continuous (p 0.319) or fast-stall (p 0.596). The LLM never sees what the target has not executed. This arm gives it that.

**Design (draft).**
- Offline, per target: replay A00's `control/<target>-r<rep>` queue (A01's warm-start point) through a source-coverage build, list functions with 0 hits (and partly covered ones with the uncovered lines), keep each one's source text. Result: a static `uncovered/<target>.jsonl` per rep.
- Stall mutator `uncovered` (`G2F_STALL_MUTATORS=...+uncovered`): pick one listed function (prefer ones called from covered code), put its source and its covered caller in the prompt, ask for a change to a working generator so its output reaches that function.
- Needs: a `.cov` build variant per target (clang `-fprofile-instr-generate -fcoverage-mapping`). Tempest has none today (`paper/` holds only `.afl`, `.asan`, `.cmp`), so it goes into the card-5 rebuild or a second build pass.
- Test: A03 warm-start arm against `control` and `afl-only`, same design as A01.

**First steps:** check whether the builders keep the target sources (`stage/paper/<bench>-<project>`), add the `.cov` variant to one target (jhead) and time the replay.
