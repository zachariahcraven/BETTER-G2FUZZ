# card-14: Verdict: do LLM stall mutators add coverage over AFL++ alone? (from A01 + A03; stop rule inside)

## Note nom-nom 2026-11-14 19:37
**Goal (user, 2026-11-14):** find more coverage from Alfred's mutator feedback than a baseline, or show there is no way forward. Decisions are taken by default from the test results and reported afterwards.

**Baseline:** `afl-only` from the same warm start (what AFL++ alone still finds after a 6 h stall), and `control` (upstream's mutators).

**Evidence so far (6 h, 15 targets, 5 reps):** A00: more LLM steps add nothing (continuous p 0.319, fast-stall p 0.596); A02: RFDM for all formats adds nothing (p 0.562). Set-up seeds do help: afl alone is lower than control on 13 of 15 targets (median ratio 0.950).

**Plan and stop rule.**
1. A01 (warm start, 2 h, 375 campaigns): control, rare, web, no-pattern, afl-only. Question: does any LLM arm beat `afl-only`?
2. A03: the arms A01 leaves alive, plus `uncovered` (card-13) and the scouts if set-up evidence supports them.
3. Verdict by 2026-11-27. **Way forward** = an arm that passes the keep rule against `afl-only` (Wilcoxon p < 0.05, no target significantly worse, no new failure kind), confirmed once with new seeds. **No way forward** = no LLM arm beats `afl-only` in A01 and none in A03, including `uncovered`; then the write-up states it with the numbers.
