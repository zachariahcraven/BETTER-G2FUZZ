# card-13: New stall mutator "uncovered": show the LLM source of target functions the queue has not reached (A03 arm)

## Note nom-nom 2026-11-14 19:37
**Why this card (evidence from A00/A02).** The stall mutators (feature, structure, pattern) mutate generators blind: 0.04-0.10 kept seeds per LLM step, in-run LLM seeds' descendants at most 1.8% of the queue, and no coverage gain for continuous (p 0.319) or fast-stall (p 0.596). The LLM never sees what the target has not executed. This arm gives it that.

**Design (draft).**
- Offline, per target: replay A00's `control/<target>-r<rep>` queue (A01's warm-start point) through a source-coverage build, list functions with 0 hits (and partly covered ones with the uncovered lines), keep each one's source text. Result: a static `uncovered/<target>.jsonl` per rep.
- Stall mutator `uncovered` (`G2F_STALL_MUTATORS=...+uncovered`): pick one listed function (prefer ones called from covered code), put its source and its covered caller in the prompt, ask for a change to a working generator so its output reaches that function.
- Needs: a `.cov` build variant per target (clang `-fprofile-instr-generate -fcoverage-mapping`). Tempest has none today (`paper/` holds only `.afl`, `.asan`, `.cmp`), so it goes into the card-5 rebuild or a second build pass.
- Test: A03 warm-start arm against `control` and `afl-only`, same design as A01.

**First steps:** check whether the builders keep the target sources (`stage/paper/<bench>-<project>`), add the `.cov` variant to one target (jhead) and time the replay.

## Note nom-nom 2026-11-14 20:07
Files: g2fuzz/py_utils/uncovered.py, g2fuzz/generator_mutation.py, g2fuzz/tests/test_uncovered.py, scripts/fuzz, build/targets/build-uncovered.sh, docs/ALFRED-ROUNDS.md, docs/ALFRED.md

## Note nom-nom 2026-11-14 20:07
**Progress 2026-11-14 20:20 MST: mutator written and tested; coverage data made for 5 targets.**

Code (uncommitted, Mac clone):
- `g2fuzz/py_utils/uncovered.py`: llvm-cov export JSON to entries (functions entered but not finished, source with never-executed lines marked `>>>`, never-called callees attached, long functions cut to a 120-line window), the pick (untried first, weight sqrt of missed lines) and the prompt.
- `g2fuzz/generator_mutation.py`: `mutation_uncovered`, switch value `uncovered` for `G2F_STALL_MUTATORS` (also in `scripts/fuzz`'s check). Reads `/targets/<target>.uncovered.json`; without the file a step does nothing.
- `g2fuzz/tests/test_uncovered.py`: 7 tests, all pass in the 01db4f3 image on Tempest (and `test_mutators` 18, `test_llm_worker` 10).
- `build/targets/build-uncovered.sh QUEUES TARGET...`: one Slurm job per target: the target's own `build.sh` with `afl-clang-fast` swapped on PATH for clang source coverage (libFuzzer harnesses get a small standalone `main`), replay of all `<target>-r*` queues, `llvm-cov export`, entries into `g2f-targets-alfred/paper/<target>.uncovered.json`.

Data from A00 control's 5 queues per target (run from a scratch copy, `~/.cache/alfred-uncov/repo`):

| target | line coverage of the queues | functions entered, not finished | lines never executed in them |
|---|---|---|---|
| jhead | 44% | 13 | 570 |
| mp3gain | 62% | 16 | 556 |
| libpcap_fuzz_both | 40% | 64 | 2,465 |
| lcms_cms_transform_fuzzer | about 30% | 124 | 1,312 |
| tiffsplit | 36% | 88 | 1,192 |

- libpng_read_fuzzer: coverage build fails at link (to fix). The other 9 round targets are submitted (jobs 1290880-1290888).
- Known limit, seen in jhead: some marked lines sit behind command-line options the fuzz run never passes (`ReadMode & READ_IMAGE`), so no input can reach them; those steps are wasted.

Next: fix libpng, check the 9, docs, then a pilot (warm start, `afl-only` / `control` / `uncovered`) once the new image carries this code.

## Note nom-nom 2026-11-14 20:07
Brief: now: mutator + tests written; coverage data made for 5 targets, 9 more building
next: fix libpng build, docs, then a warm-start pilot
you: nothing yet (a commit + push will be needed before it can go in an image)

## Note nom-nom 2026-11-14 20:16
Files: g2fuzz/py_utils/uncovered.py, g2fuzz/generator_mutation.py, g2fuzz/tests/test_uncovered.py, scripts/fuzz, build/targets/build-uncovered.sh, docs/ALFRED-ROUNDS.md, docs/ALFRED.md, experiments/A01-mutators-warm-2h/launch/study.conf, experiments/A01-mutators-warm-2h/README.md

## Note nom-nom 2026-11-14 20:16
**2026-11-14 20:35 MST: ready for commit. Coverage data exists for all 15 round targets.**

| target | queue files replayed | functions entered, not finished | lines never executed in them |
|---|---|---|---|
| bloaty_fuzz_target | 25,089 | 191 | 2,193 |
| freetype2_ftfuzzer | 99,006 | 343 | 4,448 |
| gdk-pixbuf-pixdata | 11,739 | 99 | 1,250 |
| imginfo | 11,235 | 147 | 963 |
| jhead | 6,813 | 13 | 570 |
| lcms_cms_transform_fuzzer | 2,975 | 124 | 1,312 |
| libpcap_fuzz_both | 21,297 | 64 | 2,465 |
| libpng_read_fuzzer | 9,813 | 71 | 1,199 |
| mp3gain | 6,702 | 16 | 556 |
| mp42aac | 16,720 | 83 | 585 |
| pdftotext | 34,082 | 156 | 2,920 |
| sndfile_fuzzer | 15,075 | 173 | 3,176 |
| tiffsplit | 8,073 | 88 | 1,192 |
| vorbis_decode_fuzzer | 7,002 | 29 | 219 |
| woff2_convert_woff2ttf_fuzzer | 7,673 | 23 | 198 |

- Files are in `g2f-targets-alfred/paper/<target>.uncovered.json` (36-736 KiB). gdk-pixbuf's first run had out-of-memory kills in the replay; it is being redone with the 4 GB per-run cap (job 1290903). They must be copied into the new `paper` tree when card-5 swaps it.
- Fixes since the last note: libFuzzer and `libAFLDriver.a` harnesses link a small standalone `main`; 4 GB memory cap per replay run (imginfo took the whole job's memory).
- **Default decision:** `uncovered` and `uncovered-mix` go into A01 as two more arms (525 campaigns) instead of a separate A03 round: same image, same warm starts, one round less. If this card is not committed and pushed when the targets are ready, A01 launches with its 5 arms and these two run right after as their own study.
- Tests: `test_uncovered` 7 OK, `test_mutators` 18 OK, `test_llm_worker` 10 OK (in the image on Tempest); `test_fuzz_cli.sh` PASS (198 cases) against HEAD.
- Not tested yet: a real LLM step (no image carries the code). First A01 campaigns are the test; I will read the first `uncovered` steps' logs before letting the round run on.

## Note nom-nom 2026-11-14 20:16
Brief: now: uncovered mutator, tests, data for 15 targets, 2 new A01 arms: ready
next: rebuild the image with it, then launch A01 with 7 arms
you: approve, then run: git push origin alfred

## Note nom-nom 2026-11-14 20:16
Review:
##### To check
- Diff: `g2fuzz/py_utils/uncovered.py` (new), `mutation_uncovered` in `generator_mutation.py`, one regex in `scripts/fuzz`.
- `python3 g2fuzz/tests/test_uncovered.py` on the Mac: OK (2 skipped without openai; all 7 pass in the image).
- `experiments/A01-mutators-warm-2h/launch/study.conf`: two new arm lines.
- After approving, run `git push origin alfred` so the image can be built from it.
##### Changed
New stall mutator `uncovered`: shows the LLM target source the queues never executed and asks for a generator that reaches it.
`build-uncovered.sh` makes the per-target data (done for all 15 round targets from A00 control).
A01 gets two more arms: `uncovered` and `uncovered-mix` (525 campaigns).

## Note human 2026-11-14 21:15
Approved. The change is in commit abe2246.
