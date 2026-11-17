# card-16: A03 final row (15 targets) and A04: prior run for the uncovered lists of the other 13 targets

## Note nom-nom 2026-11-16 05:20
Files: docs/ALFRED-ROUNDS.md, experiments/A04-lists-13-6h/README.md, experiments/A04-lists-13-6h/launch/study.conf, experiments/A04-lists-13-6h/launch/targets.txt

## Note nom-nom 2026-11-16 05:20
**A03 final (2026-11-16 05:20 MST), 300 of 300 campaigns, 15 targets.** freetype2's retry worked (seeds in 1 h 40 min).

| Arm vs control | Better / worse | Median ratio | Wilcoxon p | Sig. better | Sig. worse |
|---|---|---|---|---|---|
| uncovered-cont | 12 / 3 | 1.014 | 0.009 | 6 | 0 |
| uncovered (stall) | 8 / 7 | 1.002 | 0.084 | 0 | 0 |
| afl | 3 / 12 | 0.943 | 0.999 | 0 | 7 |

- freetype2: uncovered-cont 10,617 vs control 8,848 (p 0.008).
- vs AFL++ alone: uncovered-cont 13 / 2, ratio 1.198, p < 0.001, 10 sig. better, 0 worse.
- Edges summed: uncovered-cont 235,245; uncovered 214,064; control 210,371; afl 193,116.
- OOM kills: 23 of 75 uncovered-cont campaigns (card-15 fixes the cause; not in an image yet).
- Decision unchanged: keep `uncovered` in continuous mode. Rounds log row rewritten with these numbers.

**A04-lists-13-6h launched 05:35 MST:** control arm only, the 13 paper targets A00 did not run, 6 h, 2 reps. Driver 1299040, server 1299041. Purpose: queues for `build-uncovered.sh`, so that all 28 targets have a list before the check round. No decision comes from it. The study folder is on Tempest as an untracked copy (as A03's was).

## Note nom-nom 2026-11-16 05:20
Brief: now: A03 final on 15 targets: uncovered (continuous) 12 better / 3 worse, p 0.009; A04 running
next: when A04 ends (~1 day), build the lists for the 13 targets; then new image, check round
you: git push origin alfred (2 commits wait); no pull on Tempest yet

## Note nom-nom 2026-11-16 05:20
Files: docs/ALFRED-ROUNDS.md, experiments/A04-lists-13-6h/README.md, experiments/A04-lists-13-6h/launch/study.conf, experiments/A04-lists-13-6h/launch/targets.txt, scripts/lineage, scripts/tempest-image

## Note nom-nom 2026-11-16 05:20
Two small fixes added to this card:
- `scripts/lineage`: knows the origin `run-uncovered` (it was shown as `run-unknown`). Tested on A03 on Tempest: uncovered-cont's row now reads `run-uncovered`, 1,357 roots, 54,922 descendants (18.2%).
- `scripts/tempest-image`: waits up to 2 min for the new image file before the rename (the rename failed twice because the login node saw the file late). `bash -n` passes; not run end to end, the next image build is its test.

## Note nom-nom 2026-11-16 05:20
Review:
##### To check
- Open `docs/ALFRED-ROUNDS.md`, Rounds log, row A03-uncovered-6h: it reads "300 of 300 campaigns", "12 better / 3 worse", "p = 0.009".
- Open `experiments/A04-lists-13-6h/launch/targets.txt`: 13 targets, none of A00's 15.
- Open `scripts/lineage`: `"run-uncovered"` is in `CLASSES`.
##### Changed
A03's row now has the final numbers with freetype2. New study folder A04 (control only, 13 targets) for the uncovered lists; it already runs on Tempest.
`scripts/lineage` names the new mutator; `scripts/tempest-image` waits for the image file before its rename.
Lineage change tested on A03's data; the image script change is syntax-checked only.
