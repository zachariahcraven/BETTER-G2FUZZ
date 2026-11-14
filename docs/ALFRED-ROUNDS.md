# Alfred rounds: improving Alfred, one 6 h study at a time

From about 2026-11-13 (when study 05 frees the compute) to 2026-11-27, Alfred improves in rounds.
- **Each round** is a 6 h study `experiments/A<NN>-<name>`: Alfred's current defaults (`control`) against up to three
  tweaks.
- **A tweak** is a switch that changes one thing. Off, it is today's behaviour.
- **A tweak that passes the rule below** becomes the default in code before the next round.
- **When rounds end:** a 6 h check on three models, then a 24 h study on the paper's 28 targets against upstream
  G2FUZZ and AFL++ (plan: `A-check`, `A-final`). Rounds end when a round accepts nothing and the backlog has no
  candidate with evidence behind it, or on 2026-11-27.

## The acceptance rule (fixed 2026-11-09, before round A01)
`scripts/compare <study>` applies it: per target, then across targets.
- **Metric:** afl-fuzz's `edges` at the end of each campaign.
  - Within one round, every arm uses the same image and target builds, so the counts compare.
  - Across rounds, compare through each round's own control only.
- **Keep** a tweak if all of these hold:
  - its per-target median beats the control's on at least 60% of the targets (9 of 15);
  - the one-sided Wilcoxon signed-rank p on the per-target log ratios of medians is below 0.05;
  - no target is significantly worse (exact Mann–Whitney p < 0.05 with A12 ≤ 0.29);
  - it brings no new kind of failure (a failure kind the control's campaigns don't have).
- **Borderline** (0.05 ≤ p < 0.2, no target significantly worse): test it once more, in the next round, with a new
  seed set.
  - Keep it then only if it passes the keep rule.
- **Bug fixes:** keep one if its failures drop and coverage is no worse (median ratio ≥ 0.98, no target significantly
  worse).
- **Ties:** keep the cheaper version (fewer LLM calls, less GPU time).
- **Tweaks change one thing each.**
  - Fuzz-time switches share one seed generation per target (`seeds = shared`), so the arms differ only in the switch.
  - Each round regenerates the shared seeds, so the control sees a new seed set every round.
- **Setup-time switches** need `seeds = fresh` and run as a round of their own, on the targets they affect.
  `scripts/study` refuses them with shared seeds.

## Switches
`scripts/fuzz tweaks` lists them; a study arm sets them with `set:NAME=VALUE`, a single run with `--set NAME=VALUE`.

| Switch | When it acts | Values (default first) | What it changes |
|---|---|---|---|
| `G2F_LLM_MODE` | fuzzing | `stall`, `continuous` | when the worker runs an LLM step: after a stall (upstream), or one after another |
| `G2F_PLATEAU_SEC` | fuzzing | `300`, any whole number | seconds without a find before a step (stall mode) |
| `G2F_BACKOFF_SEC` | fuzzing | `60`, any whole number | extra seconds per step already run (stall mode) |
| `G2F_STALL_MUTATORS` | fuzzing | `feature+structure+pattern`; any of those and `rare`, `web`, `+`-separated | which mutators a step may pick; `rare` is Rare-Feature Directed Mutation as a stall mutator (`generator_mutation.py` `mutation_rare_feature`); `web` is the same with the feature taken from documents found on the web at that stall (`mutation_web`, [ALFRED.md](ALFRED.md#the-web-stall-mutator-2026-11-11)) |
| `G2F_WEB_SOURCES` | fuzzing | all; any of `wikipedia`, `nvd`, `stackexchange`, `github`, `links`, `+`-separated | the free sources the `web` mutator may use (`links`: pages linked from documents already read) |
| `G2F_RFDM_ALL_FORMATS` | seed generation | `0`, `1` | `1`: 3 seed-generation rounds (with Rare-Feature mutation) for every format, not only single-format targets (`program_gen.py` `setup_epochs`) |
| `G2F_SANDBOX_ALL` | seed generation and fuzzing | `0`, `1` | `1`: every generator runs in the sandbox (no network, its own `/tmp` and `/dev/shm`), not only the `web` mutator's. In 04, 3.7% of gpt-oss-20b's generators used the network, 40% on mp3gain (they download ffmpeg), so expect mp3gain to lose |

## Friday checklist (2026-11-13, when study 05 ends; before A00)
1. Read 05's ucb vs random result, and set Alfred's default scheduler from it.
2. The user commits and pushes. Build and upload the image (`scripts/tempest-image`, about an hour), and keep it
   as `build/g2fuzz-<commit>.sif`.
3. Rebuild the paper's 28 targets into `g2f-targets-alfred/paper` (`build/targets/build-paper.sh paper <project>`),
   then run the image's targets test on each.
4. Bug checks AFL-1 and AFL-2 (KNOWN_BUGS.md).
5. The web mutator and the sandbox, on the nodes the rounds use (partition `priority`, account
   `priority-quantumcore`), with the new image:
   ```bash
   srun -A priority-quantumcore -p priority -c 2 --mem 4G -t 10 bash -c '
     scripts/web-check png tiff mp4                        # every source answers or cools down; documents read
     J=${TMPDIR:-/tmp}/alfred-tmp-check-$SLURM_JOB_ID; mkdir -p $J   # a private /tmp, as campaign jobs get
     apptainer exec --cleanenv --no-mount home,cwd,tmp --bind $J:/tmp build/g2fuzz.sif \
       python3 /AFLplusplus/g2fuzz/tests/test_web.py      # the sandbox tests must run, not be skipped
     rm -rf $J'
   ```
   Not `--writable-tmpfs` without a `/tmp` bind: in that overlay, folders made under `/tmp` can't be entered
   (`Operation not permitted`), so 4 tests fail for a reason campaigns never meet (2026-11-12).
6. One short real campaign with the web mutator on a GPU server, to see a whole step:
   `scripts/fuzz run <campaign> 1800 --test --set G2F_STALL_MUTATORS=web`, then read `llm-worker.log`,
   `<target>_output/default/web_ledger.json` and `web_docs/`.
7. Launch A00 (and A02 beside it if there's room). A01 follows A00's decision.

**Results (run 2026-11-12, the day 05 ended):**
1. Scheduler: `random` for the rounds (Rounds log, first row).
2. Image e564c4e in `build/g2fuzz.sif` and `build/g2fuzz-e564c4e.sif`; the old one kept as `build/g2fuzz-d1e1695.sif`
   (the check round's `start` arm). The upload dropped once; it was resumed with `rsync --partial`.
3. All 25 projects (the 28 paper targets) built with AFL++ 5.03c and clang 18.1.8, tested in e564c4e, copied into
   `g2f-targets-alfred/paper`.
4. AFL-1 and AFL-2 fixed in 5.03c, verified (KNOWN_BUGS.md). AFL-2's `AFL_MAP_SIZE` setting stays (harmless).
5. `web-check png tiff mp4` on epyc022 (priority-quantumcore): every source answered, 14 documents per format.
   `test_web.py` 21/21, no skips, with a job-style private `/tmp`.
6. `practice/campaigns/web-jhead-1` (jhead from the image, gpt-oss-20b on an A40, 30 min, `--test`, `web` only):
   13 web steps, 12 generators (all sandboxed, no package installed), 1 nothing-new, no failures; 94 seeds handed to
   AFL++, 0 kept; ledger: 30 queries (0 errors), 55 documents from all 5 sources, 16 features with their quotes,
   16 duplicates and 1 ungrounded rejected. **Weak spot:** relevance. Several targeted features belong to related
   formats (JPEG 2000, JPEG XT, JPEG XS) or are generic Huffman-coding ideas, not features of the files jhead reads.
   **Fixed the same day:** the relevance rule (`docs/ALFRED.md`, web step 6: a feature names the part of the file
   that holds it, and the duplicate check may answer `off-format`; turned-down names are remembered). In the
   image A00 runs on, so A01's `web` arm has it.

## Each round
```bash
# launch (quantumcore first, the class priority account takes the overflow)
STUDY_EXTRA_ACCOUNT=priority-csci-591-automated-vulnerability-discovery STUDY_EXTRA_MAX=120 \
  scripts/study start A<NN>-<name> --servers --background
scripts/study status A<NN>-<name>
# when it ends (retry failed campaigns first: scripts/study start A<NN>-<name> --retry-failed ...)
scripts/study results A<NN>-<name>
srun -A group-csci-591-automated-vulnerability-discovery -p fairshare -c 1 --mem 2G -t 60 \
  scripts/compare A<NN>-<name>     # results/compare.md: decisions, per target, LLM use, failures
scripts/lineage A<NN>-<name>       # results/lineage.md: where the queue came from, per arm
```

After each round:
1. Fill in the round's row below and its README's Results.
2. Triage new failures into `docs/KNOWN_BUGS.md` and fix them.
3. Make the accepted switches the defaults in code.
4. Commit, rebuild the image (`scripts/tempest-image`), and start the next round.

Keep each round's image as `build/g2fuzz-<commit>.sif`, so a later round can run an older Alfred with `image=`.

## Backlog (in order; each with the evidence for it)
| Round | Arms | Evidence | Seeds |
|---|---|---|---|
| A00-baseline-6h | control, afl, continuous, fast-stall (120 s, no backoff) | Alfred's worker doesn't block afl-fuzz, so more steps cost no fuzzing time; also Alfred's 6 h baseline and its bug check | shared |
| A01-mutators-warm-2h | control, rare, web, no-pattern, afl-only; every campaign a warm start from A00's control/<target>-r<rep> (its queue after 6 h), LLM arms continuous, 2 h (about 1,900 steps per arm) | A00: 93% of 6 h coverage after 1 h in every arm; first stall step at 74 min; 0.07-0.10 kept LLM seeds per step, so a 6 h stall-mode round gives about 450 steps per arm; 04 lineage: stall seeds about 1% of descendants, pattern 0.7 per generator | warm (A00) |
| A02-rfdm-all-formats-6h | control, rfdm-all (4 multi-format targets) | single-format targets: Rare-Feature mutation 16.2% of 04's descendants, as much as synthesis; multi-format targets never run it (upstream code; paper Table 13: mutation ≈ 0 on exactly them) | fresh |
| A03-scouts (proposal below) | control; `library-scout` (setup: vetted, pinned writer libraries per format, their verified APIs in the generation prompt); `library-swap` (stall mutator: rewrite a working generator with another library); both | 36% of 03/04 generator failures are wrong-library-API errors; A00's freetype2 seed generation failed twice (1 generator in 5.5 h) on invented fontTools names, while 10 of 04's 12 working ttf generators wrote the bytes with `struct`; 04's mp3gain generators download ffmpeg | fresh (library-scout acts at setup) |
| A03+ | format scout (automates `program_to_format.json` for new targets: not needed for the 28 paper targets, so after A03); fonts and other wrong-library-API follow-ups | A03 | fresh |
| later | `G2F_SANDBOX_ALL=1` (safety: no generator downloads anything; a bug-fix-style rule: keep if coverage is no worse) | 3.7% of 04's generators use the network | fresh |
| later | web documents at seed generation too (the Rare-Feature rounds of `program_gen.py`), if `web` wins A01 | A01 | fresh |
| later | retests of borderline tweaks; fixes for bugs the rounds find | the rounds | – |

The generator scheduler (ucb vs random) isn't tested again here. Study 05 (24 h, 8 models) answers it, and its result
sets Alfred's default before A00: `random` (2026-11-12, Rounds log).

## A03 proposal: scouts and a library-swap mutator (2026-11-13)
Today a person writes which formats each target reads (`g2fuzz/program_to_format.json`), and the LLM picks a Python
library for each generator from memory, pip-installing whatever is missing. Both are where generators fail most.
- **Format scout** (setup, new targets): derive a target's formats from its fuzzing harness, its documentation and the
  magic bytes of its stock seeds (`file`), and write the `program_to_format.json` entry; a person confirms it. The 28
  paper targets already have entries, so this serves new targets (the latest versions, Butler's) more than the rounds.
- **Library scout** (setup, per format): search PyPI, GitHub and Wikipedia (the web mutator's free sources) for
  libraries that write the format, plus "no library: `struct`" as a candidate. For each candidate: install a pinned
  version into the campaign (outside the sandbox, from a vetted list, before any web-informed code runs), import it,
  and record its version and the real names of the classes and functions a generator needs (from `dir()`/`help()`,
  not from the web). The code-generation prompt then lists only installed, checked libraries with their real API
  names. Remembered per format in the campaign (`library_ledger.json`, beside `web_ledger.json`).
- **Library-swap mutator** (a stall mutator, `G2F_STALL_MUTATORS=libswap`): take a working generator and rewrite it
  with a different checked library (or with `struct`). Different encoders make different, still valid, files of the
  same features, a cheap source of variety at a stall.
- **Safety:** libraries come from a vetted index (PyPI only, pinned versions, no install from web-found URLs); install
  happens at setup, outside generator code; generators still can't install anything when `G2F_SANDBOX_ALL=1`.
- **Round A03:** arms control, `library-scout` (setup switch, fresh seeds), `library-swap` (stall switch) and both.
  Primary measures: seed-generation success (generators per format, no-seed runs, wrong-API errors), then coverage.
  Font targets (freetype2, woff2) and mp3gain are where it should show.

## Rounds log
| Round | Image (commit) | Arms | Result | Decision |
|---|---|---|---|---|
| 05 vs 04 (BETTERG2FUZZ, 24 h, 15 targets, 8 models) | – | `random` (05) vs `ucb` (04) | gpt-oss-20b: random's median edges higher on 10 of 15 targets, median ratio 1.00, exact Wilcoxon one-sided p = 0.084 for random > ucb (0.92 for ucb > random); imginfo 1.59, lcms 1.24. Every model's median ratio 1.00 (afl's, the between-study noise: 1.00, 6 above / 9 below). Cross-study medians, not yet 05's replayed-coverage analysis | `scheduler = random` in A00-A02: ucb adds nothing, random costs the same and is upstream's (a tie: the simpler; one difference fewer from upstream in the final study). `scripts/fuzz`'s own default stays `ucb` for manual runs |
| A00-baseline-6h | – | control, afl, continuous, fast-stall | – | – |
