# card-6: Launch A01-mutators-warm-2h, then A03 scouts; rounds stop 2026-11-27

## Note nom-nom 2026-11-13 17:15
Waits on card-3 (A00's winner is A01's control) and card-5 (new image and targets).

Plan: 6 h tweak rounds `experiments/A<NN>-*` on gpt-oss-20b, 15 targets x 5 reps, control + up to 3 arms. Keep going until nothing improves or 2026-11-27. A03 "scouts" proposal is in `docs/ALFRED-ROUNDS.md`.

Compute: priority-quantumcore (OK'd until 2026-12-18) + the class priority account.

## Note nom-nom 2026-11-14 21:03
**A01 launched 2026-11-14 20:59 MST** on image `abe2246` and the new targets.

- 525 campaigns of 2 h: 15 targets x 5 reps x 7 arms (control, rare, web, no-pattern, uncovered, uncovered-mix, afl-only), each a warm start from A00 `control/<target>-r<rep>`.
- Driver job 1291126 (`--servers --background`, extra account priority-csci-591..., max 120), LLM server job 1291127 on gpu058 (qc-h100, 14 h).
- Started with `LOCALDOMAIN=rci.montana.edu APPTAINERENV_LOCALDOMAIN=rci.montana.edu SBATCH_NO_REQUEUE=1` (compute-node DNS still broken at 19:35).
- First check: the first `uncovered` steps' worker logs (a real-model run of the new mutator); if they fail I stop only the two `uncovered` arms.

## Note nom-nom 2026-11-14 21:03
Brief: now: A01 launched 20:59 (525 campaigns, 7 arms, image abe2246, new targets)
next: read the first uncovered steps, then compare when it ends
you: nothing

## Note nom-nom 2026-11-14 21:12
**First real-model check of `uncovered`, 21:12 MST: works.** In `uncovered/jhead-r1`, step 1 picked `makernote.c:ProcessCanonMakerNoteDir` (18 lines never executed) and made generator `jpg-28.py`; step 2 picked `exif.c:ProcessExifDir` (36 lines) and made `xmp-29.py`. Steps take 21-95 s and hand 1-3 seeds to AFL++ each. 33 jobs running at 21:12; the driver launches the rest as room allows. Both `uncovered` arms stay in the round.

## Note nom-nom 2026-11-15 00:31
**Interim, 2026-11-15 00:30 MST: 239 of 525 done, 67 fuzzing, 219 to launch, none failed.** 7 of 15 targets complete (pdftotext 4 of 5 reps). Compared against `afl-only` (scratch results folder `~/.cache/nomnom-clitest/A01-mutators-warm-2h`, `--no-triage`):

| arm | better / worse (of 7) | median ratio | Wilcoxon p | sig. better |
|---|---|---|---|---|
| control | 3 / 3 | 1.000 | 0.500 | 0 |
| rare | 2 / 4 | 0.999 | 0.781 | 0 |
| web | 1 / 4 | 0.997 | 0.969 | 0 |
| no-pattern | 3 / 4 | 0.999 | 0.656 | 0 |
| **uncovered** | **6 / 1** | **1.033** | **0.016** | 1 (pdftotext) |
| uncovered-mix | 5 / 2 | 1.001 | 0.188 | 0 |

`uncovered` per target (median edges, arm vs afl-only): jhead 577 vs 564; gdk-pixbuf 2,284 vs 2,139 (p 0.056); imginfo 3,385 vs 1,968 (ratio 1.72, p 0.111, so not every rep); tiffsplit 1,780 vs 1,704; mp3gain 944 vs 945; mp42aac 1,977 vs 1,951; pdftotext 7,278 vs 7,046 (p 0.029). Half the round only: no decision yet.

## Note nom-nom 2026-11-15 05:12
**A01 final, 2026-11-15 05:10 MST: 525 of 525 done, none failed or short.** Reports on Tempest in `experiments/A01-mutators-warm-2h/results/`: `compare-vs-afl-only.md`, `compare.md` (against control), `lineage.md`.

Against `afl-only` (AFL++ alone from the same stalled queue), 15 targets, 5 reps:

| arm | better / worse | median ratio | Wilcoxon p | sig. better / worse | default decision |
|---|---|---|---|---|---|
| control (feature, structure, pattern) | 6 / 5 | 1.000 | 0.517 | 0 / 0 | no gain |
| rare | 3 / 7 | 1.000 | 0.862 | 0 / 0 | drop |
| web | 3 / 6 | 1.000 | 0.973 | 0 / 0 | drop (6 kept seeds in 2,715 steps) |
| no-pattern | 7 / 7 | 1.000 | 0.643 | 0 / 0 | drop |
| **uncovered** | **11 / 2** | **1.013** | **0.003** | **2 / 0** | passes the coverage test: repeat with new seeds (A03) |
| uncovered-mix | 9 / 4 | 1.001 | 0.122 | 1 / 0 | drop (diluted) |

- `uncovered` per target (median edges vs afl-only): pdftotext 7,276 vs 7,053 (p 0.008), sndfile 2,927 vs 2,836 (p 0.008), imginfo 3,385 vs 1,968 (p 0.111), gdk-pixbuf 2,284 vs 2,139 (p 0.056), bloaty 5,909 vs 5,864 (p 0.056), freetype2 9,769 vs 9,538 (p 0.095), tiffsplit 1,780 vs 1,704, jhead 577 vs 564, mp42aac 1,977 vs 1,951; flat on mp3gain, lcms, vorbis, woff2, libpng; libpcap 2,411 vs 2,439 (not significant).
- Against control: uncovered 12 / 2, p 0.002.
- Edges gained in the 2 h, summed over each arm's 75 campaigns: uncovered 9,887; uncovered-mix 5,442; control 1,969; no-pattern 1,944; rare 1,901; web 1,368. 71% of uncovered's gain falls in the 10 min after a step with a kept seed (18% of the run time).
- Lineage: 54.8% of the uncovered arm's new queue entries descend from its LLM seeds (8,957 of 16,349; 1,829 with new coverage). In A00 that share was at most 1.8%. (`scripts/lineage` labels them `run-unknown`: it does not know the mutator's name yet.)
- Kept seeds per step are no higher than for the blind mutators (0.08): the gain comes from what the kept seeds open up, not from more seeds being kept.
- Flag: 7 of 75 uncovered campaigns had one out-of-memory kill of a child process (rare 1, no-pattern 1, uncovered-mix 1, control and afl-only 0). All 7 ran their full 7,200 s, so it was a generator or a target run, not the campaign. To watch in A03.

**A03-uncovered-6h launched 05:15 MST** (the repeat with new seeds, from a cold start): control, afl, uncovered (stall mode), uncovered-cont; 300 campaigns of 6 h, fresh shared seeds. Driver 1294137, server 1294138. The study folder was copied to Tempest by rsync (it is not in git there yet): delete the untracked `experiments/A03-uncovered-6h/launch` and `README.md` on Tempest before the next pull, or the pull will refuse.

## Note nom-nom 2026-11-15 05:12
Files: docs/ALFRED-ROUNDS.md, experiments/A03-uncovered-6h/README.md, experiments/A03-uncovered-6h/launch/study.conf, experiments/A03-uncovered-6h/launch/targets.txt

## Note nom-nom 2026-11-15 05:12
Brief: now: A01 done: uncovered beats AFL++ alone on 11 of 15 (p 0.003); others no gain
next: A03 (new seeds, cold start, 6 h) running; compare when it ends
you: nothing needed; do not pull on Tempest until I say (untracked A03 folder)

## Note nom-nom 2026-11-15 21:05
**A03 result (2026-11-15 21:00 MST), 14 of 15 targets, 285 of 300 campaigns**

Against control (5 reps per target, 6 h, cold start, new seeds):

| Arm | Better / worse | Median ratio | Wilcoxon p | Sig. better | Sig. worse |
|---|---|---|---|---|---|
| uncovered-cont | 11 / 3 | 1.009 | 0.018 | 5 | 0 |
| uncovered (stall) | 7 / 7 | 1.001 | 0.148 | 0 | 0 |
| afl | 3 / 11 | 0.941 | 0.998 | 0 | 7 |

- uncovered-cont significantly better: imginfo 3,559 vs 1,970; gdk-pixbuf 2,586 vs 2,315; pdftotext 7,665 vs 6,964; sndfile 3,062 vs 2,832; tiffsplit 1,838 vs 1,731. Lowest: woff2 1,289 vs 1,413 (p 0.31).
- Against AFL++ alone: uncovered-cont 12 / 2, ratio 1.144, p 0.002, 9 sig. better, 0 worse.
- Stall mode: median 6 LLM steps in 6 h (continuous: 348). Too few to matter from a cold start.
- Not continuous mode alone: A00's continuous arm (upstream mutators) had none of these gains (p 0.319).
- Lineage: 17.4% of uncovered-cont's queue descends from seeds made in the run (control under 0.1%).
- Flag: 21 of 70 uncovered-cont campaigns had OOM kills of child processes; all ran 21,600 s. Control: 0.

**Decision: keep `uncovered` in continuous mode.** A03 is the repeat with new seeds that A01 needed.

freetype2: seed generation hit the 5.5 h limit. Old driver 1294137 cancelled (it was idle); retried with `--retry-failed`, `G2F_SEEDGEN_MIN=480`: driver 1297974, server 1297975. Results on Tempest: `experiments/A03-uncovered-6h/results/` (compare.md, compare-vs-afl.md, lineage.md).

## Note nom-nom 2026-11-15 21:05
Brief: now: A03 done on 14 targets: uncovered (continuous) beats control, p 0.018; kept
next: freetype2 retry running (ends ~11:00 Mon); then memory limit for generator scripts
you: approve this card, then git push origin alfred; no pull on Tempest yet

## Note nom-nom 2026-11-15 21:05
Review:
##### To check
- Open `docs/ALFRED-ROUNDS.md`, Rounds log: rows A01-mutators-warm-2h and A03-uncovered-6h are there, A03's decision reads "Keep `uncovered` in continuous mode".
- Open `experiments/A03-uncovered-6h/launch/study.conf`: 4 arms (control, afl, uncovered, uncovered-cont).
##### Changed
Rounds log gets the A01 and A03 results and decisions; the A03 study folder is added (it already ran on Tempest from a direct copy).
Docs and study config only, no code. Numbers come from `scripts/compare` output on Tempest.

## Note human 2026-11-15 21:19
Approved and committed (5edec44).
