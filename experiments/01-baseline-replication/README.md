# 01 Baseline replication

**Question:** does G2FUZZ beat AFL++(cmplog) on the paper's targets with our setup, as in the paper's Table 1?
We rerun the paper's evaluation before changing anything, so later studies have a baseline on our own setup.
**Status:** done: phase B (2026-10-25) and phase C (2026-10-26), both analyzed. **Design and dated changes:** [PLAN.md](PLAN.md).
**Differences from the paper:** [DRIFT.md](DRIFT.md).
**Paths since 2026-10-29:** the repo folder is `BETTERG2FUZZ` (was `WORKING-BETTERG2FUZZ`) and the target build
scripts are in `build/targets/` (was `targets/paper/`); this study's scripts, logs and campaigns keep the old paths.

## Arms
| Arm | Repo | AFL++ | What runs |
| --- | --- | --- | --- |
| `g2432` | WORKING-BETTERG2FUZZ | 4.32c | G2FUZZ: LLM seed generation, then fuzzing with LLM mutation steps |
| `afl432` | WORKING-BETTERG2FUZZ | 4.32c | AFL++(cmplog), the paper's baseline: `scripts/fuzz run --afl`, stock seeds |
| `g2503` | G2FUZZ-upgradedAFL | 5.03c | G2FUZZ |
| `afl503` | G2FUZZ-upgradedAFL | 5.03c | AFL++(cmplog) |

Model for the G2FUZZ arms: `Qwen3.8-27B-FP8-nothink` (vLLM). Why: [setup/](setup/README.md#model-bake-off-2026-10-23).
Each arm runs with its own repo's scripts and image; all campaign data is kept here in one place.

## Phases
| Phase | What | Status |
| --- | --- | --- |
| Setup | Which model? Do all 4 arms work end to end? ([setup/](setup/)) | done |
| B | UNIFUZZ: 10 programs x 4 arms x 5 reps x 6 h = 200 campaigns | done (2026-10-23 13:13 to 2026-10-24 22:27) |
| C | The paper's 24 h x 5, scoped (2026-10-25) to exiv2, gdk-pixbuf-pixdata, imginfo, jhead, mp3gain with the 4.32c arms: `launch/phaseC.sh`, 50 campaigns; MAGMA and FuzzBench later | done (2026-10-26) |

## Layout
| Folder | Holds |
| --- | --- |
| `launch/` | `phaseB.sh`: the exact commands behind every phase B campaign |
| `analysis/` | Coverage replay on one common binary, ASan bug triage, statistics |
| `results/` | Report tables and figures |
| `campaigns/` | Data, git-ignored. `B-<program>-<arm>-r<rep>`, e.g. `B-mp42aac-g2503-r3` |
| `setup/` | The checks that decided how to run the study (not results) |

Look at a campaign: `G2F_EVAL=$PWD/campaigns scripts/fuzz results B-mp42aac-g2503-r3` from the arm's repo
(`afl432`/`g2432`: WORKING-BETTERG2FUZZ, `afl503`/`g2503`: G2FUZZ-upgradedAFL).

## Results (phase B, 6 h x 5; full tables in [results/REPORT.md](results/REPORT.md))
Edges = every final queue replayed on one common binary (4.32c `.afl`); bugs = crashes rerun on the `.asan` build,
deduplicated by bug type + top 3 frames (UNIFUZZ's rule). Exact Mann-Whitney U on 5 vs 5 reps, A12 = Vargha-Delaney.

- **Edges: G2FUZZ > AFL++(cmplog) on 8 of 10 programs with both AFL++ versions** (4.32c: significant at p < 0.05 on
  tiffsplit, ffmpeg, mp42aac, pdftotext; 5.03c: also exiv2 and gdk-pixbuf-pixdata). AFL++ ahead on imginfo (4.32c)
  and mp3gain (5.03c), neither significant. flvmeta is saturated: 232 edges in all 20 campaigns.
- **Bugs: G2FUZZ ahead on 6 of 10 programs** (significant: jhead 28 vs 15, pdftotext 5 vs 3, mp42aac 2 vs 0 with
  4.32c); AFL++ ahead on gdk-pixbuf-pixdata and tiffsplit (not significant); ties on flvmeta and (4.32c) ffmpeg.
- **Sign agreement with the paper's Table 1:** 32/40 cells against the GPT-4 column, 23/40 against GPT-3.5 (per
  program x AFL++ version x metric; the paper's ties count as disagreement unless we tie too).
- **Where the gain comes from:** the LLM seeds. In G2FUZZ arms the initial seeds alone cover 26-37% of the final
  edges on exiv2 and 39-44% on tiffsplit (stock seeds: 9% and 26%); in-run LLM mutation steps were rare (293 steps
  over 100 campaigns, 27 campaigns had none). Throughput was equal within an AFL++ version (median execs/s ~560 for
  both 4.32c arms, ~710 for both 5.03c arms), so the edge differences are search effects, not speed.
- **AFL++ 4.32c vs 5.03c:** mixed. AFL++(cmplog) 5.03c covers more on exiv2, mp3gain, mp42aac, pdftotext and less on
  ffmpeg (all significant), gdk-pixbuf and imginfo (not); G2FUZZ shifts the same way but less. Bugs: no significant
  difference except ffmpeg (G2FUZZ 1 vs 0).
- **Triage caveat:** AFL++ saved 16,041 crashes; 10,590 reproduce as ASan bugs, 3,263 run clean on the ASan build,
  1,878 hang there and 285 are killed for memory. Of the 1,218 mp42aac crashes in the AFL++ arms only 3 give an ASan
  report; the rest are SIGABRTs that run clean, hang or exhaust memory on the ASan build (memory exhaustion under
  `afl-fuzz -m 1024`). An abort without a memory error counts as a bug type (`ABRT`, ASan's deadly-signal report):
  most mp42aac bugs in the G2FUZZ arms are of that kind (113 ABRT, 15 SEGV, 8 heap-buffer-overflow crash files).
- **Second triage rule (DRIFT.md 5.10):** with ASan's allocation cap at 1 GB, 14,865 of the 16,041 crashes give a
  report (4,485 of them `allocation-size-too-big`). Medians rise where memory exhaustion was common: mp42aac
  G2FUZZ 10 vs AFL++ 4 (strict: 2 vs 0), exiv2 14 vs 15 (8 vs 8), tiffsplit 9 vs 8 (5 vs 5), pdftotext 7 vs 5
  (5 vs 3); jhead, mp3gain, imginfo, flvmeta, ffmpeg unchanged. Directions and significance are the same as under
  the strict rule except exiv2 with 4.32c, which turns into a non-significant tie (`bugs_cap_med`, `unique_bugs_cap`).
- Campaign notes: `B-ffmpeg-g2503-r5` fuzzed 5 h 44 min (seed generation took 2 h 46 min; the job limit cut it);
  `B-mp42aac-g2503-r3` ran with `AFL_IGNORE_SEED_PROBLEMS=1` (DRIFT.md 5.7; tests without it in
  `results/tests-excl-flagged.tsv`, same conclusions).

## Results (phase C, 24 h x 5 on the five UNIFUZZ programs, AFL++ 4.32c arms; full tables in [results/phase-C/REPORT.md](results/phase-C/REPORT.md))
Same measurements as phase B (common-binary replay for edges, ASan rerun + UNIFUZZ rule for bugs, exact Mann-Whitney U
on 5 vs 5 reps). 50 campaigns (exiv2, gdk-pixbuf-pixdata, imginfo, jhead, mp3gain x G2FUZZ/AFL++(cmplog) x 5 reps),
all started 2026-10-25 09:18-09:40, 24 h of fuzzing each, both G2FUZZ arms of a group on the same LLM server.

- **Edges: G2FUZZ >= AFL++(cmplog) on all 5 programs** (phase B at 6 h: 4 of 5, imginfo was behind). Significant on
  gdk-pixbuf-pixdata (2184 vs 2111, A12 0.92, p 0.032); exiv2 6995 vs 5792 (A12 0.80, p 0.15 with all five AFL++ reps;
  A12 1.0, p 0.016 without the damaged rep, see below); imginfo 2024 vs 2019, jhead 508 vs 501, mp3gain 871 vs 871
  (ties within noise). The 6 h -> 24 h gain is small for both arms (exiv2 G2FUZZ 5712 -> 6995, AFL++ 5611 -> 5792;
  the other four programs +1-4%).
- **Bugs: G2FUZZ ahead on all 5 programs** (phase B: 3 of 5, gdk-pixbuf-pixdata and the exiv2 tie flipped). Significant
  on jhead (35 vs 13, A12 0.96, p 0.016; phase B 28 vs 15). gdk-pixbuf-pixdata 14 vs 5 (p 0.65, wide spread: the
  arm unions are 27 vs 18), exiv2 12 vs 10, imginfo 3 vs 2, mp3gain 9 vs 8. The 1 GB-cap rule gives the same
  directions (exiv2 22 vs 20, gdk-pixbuf-pixdata 22 vs 7, the rest unchanged).
- **Sign agreement with the paper's Table 1** on these 10 cells (5 programs x 2 metrics, 4.32c): 7/10 against the GPT-4
  column, 5/10 against GPT-3.5 (phase B on the same cells: 7/10 and 3/10). The disagreements are all cells where the
  paper has AFL++ ahead or a tie on jhead/mp3gain/imginfo and we see G2FUZZ ahead.
- **Where the gain comes from:** still the LLM seeds. The initial seeds alone cover 27-36% of the final edges on exiv2,
  44-48% on gdk-pixbuf-pixdata, 72-83% on mp3gain (stock seeds: 9%, 38%, 57%). In-run LLM mutation steps were more
  frequent than in phase B (537 steps in 25 campaigns, median 6-34 per campaign, none without) because the 24 h runs
  plateau more often; the edge gap did not widen with them. Throughput equal within noise (median execs/s G2FUZZ 544 vs
  AFL++ 499 on exiv2, 1168 vs 1439 on imginfo, 252 vs 288 on mp3gain).
- **Triage:** 6,170 crash files; 4,823 reproduce as ASan bugs, 1,247 run clean, 88 hang, 12 are killed for memory
  (5,789 give a report under the 1 GB cap). No mp42aac-style SIGABRT problem on these five programs.
- **Damaged campaign `C-exiv2-afl432-r3`** (job 886197): AFL++ aborted itself at 21 h 53 min ("Incorrect fuzzing setup
  detected ... 45028 of 45027/45056", afl-fuzz-stats.c:781). The coverage map was corrupted by the target from 20 h 23 min
  on: own-binary edges went 7.6k -> 45,027 (the full map), the queue 4,863 -> 24,018 entries, saved crashes 183 -> 603.
  The corrupted inputs corrupt the map on the replay binary too (edges_final 55,350 vs 5.6-5.9k for its siblings), so the
  campaign is kept in `campaigns.tsv` (`complete=short(78796)`) but the tests are repeated without it in
  `results/phase-C/sensitivity-excl-exiv2-afl432-r3/` (5 vs 4 reps on exiv2: edges A12 1.0, p 0.016; bugs 12 vs 10,
  A12 0.85, p 0.079; all other programs unchanged). Its crash triage is valid (604 files -> 517 ASan reports, 27 buckets).
  Kept, not rerun (DRIFT.md 5.11).
- Other campaign notes: 49 of 50 ran the full 86,400 s; seed generation took 3-68 min (median 29; allowance 210 min).
