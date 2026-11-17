# card-14: Verdict: do LLM stall mutators add coverage over AFL++ alone? (from A01 + A03; stop rule inside)

## Note nom-nom 2026-11-14 19:37
**Goal (user, 2026-11-14):** find more coverage from Alfred's mutator feedback than a baseline, or show there is no way forward. Decisions are taken by default from the test results and reported afterwards.

**Baseline:** `afl-only` from the same warm start (what AFL++ alone still finds after a 6 h stall), and `control` (upstream's mutators).

**Evidence so far (6 h, 15 targets, 5 reps):** A00: more LLM steps add nothing (continuous p 0.319, fast-stall p 0.596); A02: RFDM for all formats adds nothing (p 0.562). Set-up seeds do help: afl alone is lower than control on 13 of 15 targets (median ratio 0.950).

**Plan and stop rule.**
1. A01 (warm start, 2 h, 375 campaigns): control, rare, web, no-pattern, afl-only. Question: does any LLM arm beat `afl-only`?
2. A03: the arms A01 leaves alive, plus `uncovered` (card-13) and the scouts if set-up evidence supports them.
3. Verdict by 2026-11-27. **Way forward** = an arm that passes the keep rule against `afl-only` (Wilcoxon p < 0.05, no target significantly worse, no new failure kind), confirmed once with new seeds. **No way forward** = no LLM arm beats `afl-only` in A01 and none in A03, including `uncovered`; then the write-up states it with the numbers.

## Note nom-nom 2026-11-15 05:12
**Status 2026-11-15: a candidate way forward exists.** A01 (warm start, 2 h): upstream's mutators, `rare`, `web` and `no-pattern` add nothing over AFL++ alone (p 0.52 to 0.97). The new `uncovered` mutator (card-13) does: 11 of 15 targets higher, median ratio 1.013, p = 0.003, two targets significant, none significantly worse, and 54.8% of its new queue entries descend from its LLM seeds. Details on card-6.

Not a verdict yet: the stop rule asks for one repeat with new seeds. That is A03-uncovered-6h (cold start, 6 h, against control and afl), launched 2026-11-15 05:15. Keep if `uncovered` (stall or continuous) passes the keep rule against control there.

## Note nom-nom 2026-11-15 21:05
**Verdict (2026-11-15): yes, there is a way forward.** The `uncovered` mutator (coverage feedback: source of entered-but-unfinished functions) in continuous mode passes the keep rule twice with different seeds:
- A01 (warm start, 2 h): 11 / 2 vs AFL++ alone, p 0.003.
- A03 (cold start, 6 h, new seeds): 11 / 3 vs control, p 0.018, 5 targets sig. better, 0 worse; 12 / 2 vs AFL++ alone, p 0.002.

The blind mutators (rare, web, no-pattern, rfdm-all) and mode changes alone (continuous, fast-stall) gave no gain.

Open: freetype2 in A03 (retry running), OOM kills of child processes in 21 of 70 continuous campaigns, uncovered lists come from A00 control queues (a real campaign must make them itself or get them from a prior run).
