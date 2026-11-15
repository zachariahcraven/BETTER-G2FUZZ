# card-3: A00 analysis: pick the winner that feeds A01's control

## Note nom-nom 2026-11-13 17:15
Waits on card-2 (A00's freetype2 reruns). Tools: `scripts/compare`, `scripts/lineage`. Acceptance rule is in `docs/ALFRED-ROUNDS.md`.

Unexplained so far: lcms continuous 438 edges vs control 1179.

A00's winner becomes A01's control, so A01 (card-6) waits on this decision.

## Note nom-nom 2026-11-13 18:00
**Partial A00 analysis, 2026-11-13** (285 done campaigns; freetype2's 15 are missing, so 14 of 15 targets). Run read-only from a scratch copy on Tempest (`~/.cache/nomnom-clitest/A00-baseline-6h`, campaigns symlinked; full report there in `results/compare.md`). Nothing was written into the study folder.

**Decisions by the rule (`scripts/compare`, control = control):**

| arm | better / worse | median ratio | Wilcoxon p | sig. worse | decision |
|---|---|---|---|---|---|
| continuous | 11 / 3 | 1.006 | 0.174 | 0 | borderline (and a new failure kind, see below) |
| fast-stall | 6 / 7 | 1.000 | 0.420 | 0 | drop |
| afl (baseline) | 2 / 12 | 0.966 | – | 8 | no decision |

- **freetype2 cannot make continuous a "keep".** With the best possible freetype2 result p is 0.112, with the worst 0.334. It stays borderline or drops.
- The gains are small: continuous beats control by 0.2% to 5.2% on its 11 better targets; no target is significantly better.
- Control clearly beats plain AFL++ on 8 of 14 targets (libpcap 2,341 vs 1,126; mp42aac 1,950 vs 1,295; pdftotext 7,019 vs 5,644).

**lcms (continuous 438 vs control 1,179): a two-outcome target, in every arm.**
- A run ends near 410-476 edges or near 1,140-1,240. Runs that reach the high state mostly do so in the first 61 s; a few later (617 s, 975 s, 1,189 s, 12,287 s); some never.
- Reached the high state: afl 4 of 5, control 4 of 5, fast-stall 4 of 5, continuous 1 of 5. Continuous against the other three together: Fisher exact p = 0.031.
- The generated seeds do not help: all 84 lcms seeds take the same path (afl-fuzz's start-up log shows map size 44 and one hash for every seed), and the plain-AFL++ arm with 1 stock seed shows the same split.
- So the 438 is 4 unlucky-or-hindered runs, not uniformly lower coverage. Whether continuous mode lowers the chance of the breakthrough is not settled by 5 reps: that is the open question. Without lcms, continuous has p = 0.061.

**New failure kind in continuous: OURS-7 (card-12).** The LLM worker died partway in continuous mp42aac-r3/r4/r5, so those ran 35% to 61% of the time without the LLM. Continuous mp42aac's median (1,962 vs 1,950) includes them.

**Other notes:**
- "queue file >1 MiB" shows 15 campaigns per LLM arm. These are start-up seeds from the shared seed set (bloaty 1, jhead 1, sndfile 9 per campaign, e.g. a 4.2 MB `orig:elf-54_...`), the same in all three arms, not in-run seeds (G2F-1). `scripts/compare`'s count does not tell the two apart.
- OOM kill: 1 campaign each in control and fast-stall.
- Kept LLM seeds are rare: continuous median 5 kept of 235 handed over per campaign; fast-stall 1 of 49; control 0 of 6.

**Still to do for the decision:** freetype2 reruns (card-2); decide on rerunning the 3 mp42aac campaigns; then the final `scripts/compare` and `scripts/lineage` on the real study folder. `scripts/lineage` not run yet.

**My read (nom-nom's interpretation):** neither arm passes "keep". Continuous is the better candidate but its evidence is weak (borderline, tiny gains, lcms unexplained, 3 crippled mp42aac runs). The rule says a borderline arm is tested again once with new seeds; that, or keeping control as A01's control, is the user's call.

## Note nom-nom 2026-11-13 18:01
Brief: now: partial analysis on 14 of 15 targets: continuous borderline (p 0.179), fast-stall drop
next: final compare + lineage once the freetype2 reruns finish (card-2)
you: decide whether continuous mp42aac-r3/r4/r5 are rerun (card-12)

## Note nom-nom 2026-11-13 18:01
Correction to the note above: the report's Wilcoxon p for continuous is **0.179** (the table says 0.174, which I recomputed from the ratios rounded to 3 places). The freetype2 best/worst cases (0.112 / 0.334) and the without-lcms figure (0.061) come from the same rounded ratios, so read them as approximate; the conclusion (freetype2 cannot bring continuous under 0.05) does not depend on the third decimal.

## Note nom-nom 2026-11-14 00:51
**Final A00 analysis, 2026-11-14 00:51 MST (all 315 campaigns done; freetype2 reruns ended 00:39, no worker crash).**

Reports on Tempest in `experiments/A00-baseline-6h/results/` (untracked): `compare.md`, `lineage.md`, `lineage.csv`. `compare.md` was made with the card-11 version of `scripts/compare` (scratch copy), because the Tempest checkout is still at f8ddcbb.

| arm | better / worse (of 15) | median ratio | Wilcoxon p | sig. better / worse | rule's decision |
|---|---|---|---|---|---|
| continuous | 11 / 4 | 1.006 | 0.319 | 0 / 0 | drop (also new failure kind: worker traceback, OURS-7) |
| fast-stall | 6 / 8 | 0.999 | 0.596 | 1 / 0 (bloaty) | drop |
| afl (baseline) | 2 / 13 | 0.950 | 0.999 | 0 / 8 | – |

- **Control wins by the rule**: neither tweak arm reaches "keep". Continuous's p went from 0.179 (14 targets) to 0.319 with freetype2 (ratio 0.958).
- freetype2: control 9,517, continuous 9,114, fast-stall 9,148, afl 8,767 (medians; none significant).
- lcms still drives continuous's worst ratio (0.372, 1 of 5 runs on the high path); cause unknown.
- Coverage after LLM steps: continuous 18.7% of run edges in windows covering 13.9% of time; fast-stall 4.7% / 5.5%; control 1.2% / 0.9%.
- Lineage: descendants of in-run LLM seeds are 1.8% of continuous's queue entries (4,604 of 266,700; 432 with new coverage), 0.5% for fast-stall, 0.1% for control. Feature seeds give the most descendants per generator in continuous (1.1), structure in fast-stall (1.1).
- Open: the 3 continuous mp42aac runs with a dead worker (OURS-7) are still in the data; mp42aac's continuous ratio is 1.006 with them.

## Note nom-nom 2026-11-14 00:51
Brief: now: final compare + lineage done on all 315; by the rule both tweak arms drop, control wins
next: nothing until you decide
you: confirm control feeds A01 (or ask for a continuous retest); decide on 3 mp42aac reruns

## Note nom-nom 2026-11-14 00:51
Review:
##### To check
- Read the last note on this card (decision table).
- On Tempest: `less experiments/A00-baseline-6h/results/compare.md`, section "Decisions".
- Decide: control feeds A01, or retest continuous with new seeds.
##### Changed
Final A00 analysis on all 315 campaigns: compare.md, lineage.md, lineage.csv in the study's results/ on Tempest.
By the acceptance rule both tweak arms drop (continuous p 0.319, fast-stall p 0.596), so control feeds A01.
No repo files changed.

## Note human 2026-11-14 08:26
Changes requested: control feeds A01

## Note nom-nom 2026-11-14 08:26
**Decision (user, 2026-11-14): control feeds A01.** Both tweak arms dropped.

- A01's `launch/study.conf` already takes its warm starts from `A00-baseline-6h/campaigns/control/{target}-r{rep}`; no config change needed.
- Recorded result and decision in the Rounds log row for A00 in `docs/ALFRED-ROUNDS.md` (image 01db4f3).
- The 3 continuous mp42aac runs (OURS-7) are not rerun: continuous is dropped, so they no longer matter for a decision.

## Note nom-nom 2026-11-14 08:26
Brief: now: decision recorded: control feeds A01; Rounds log row for A00 filled in
next: nothing; A01 waits on the deploy window (card-5)
you: approve (commits docs/ALFRED-ROUNDS.md)

## Note nom-nom 2026-11-14 08:26
Files: docs/ALFRED-ROUNDS.md

## Note nom-nom 2026-11-14 08:26
Review:
##### To check
- Open the diff of `docs/ALFRED-ROUNDS.md`: one table row changed (A00-baseline-6h).
- Check the Decision cell reads "control stays the default and feeds A01's warm starts".
##### Changed
Recorded your decision: control feeds A01, both tweak arms dropped.
Filled in A00's row in the Rounds log (docs/ALFRED-ROUNDS.md) with the result and decision.
A01's study.conf already points at A00 control; no change there.

## Note human 2026-11-14 19:30
Approved and committed (d433c92).
