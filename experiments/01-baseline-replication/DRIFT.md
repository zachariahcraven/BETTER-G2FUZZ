# Drift from the paper's setup

Every place where our setup for the baseline replication differs from what the G2FUZZ authors tested (USENIX Security
2025). WORKING-BETTERG2FUZZ runs AFL++ 4.32c, G2FUZZ-upgradedAFL AFL++ 5.03c; both with a local model.
Status: **accepted** = decided; **review** = still open (the study owner confirms or rejects). Started 2026-10-22.

## 1. Targets and versions

| # | Drift | Why | Status |
|---|---|---|---|
| 1.1 | Latest-release builds for FuzzBench (12 projects) and MAGMA (4) | Paper only fuzzes latest versions for UNIFUZZ (section 5.1.4, Table 4). FuzzBench latest rows are already built; MAGMA latest rows will be **skipped** (default) | accepted (2026-10-25) |
| 1.2 | woff2 latest = current OSS-Fuzz build (oss-fuzz@284f6239) | Paper-era recipe can't build woff2 1.0.2 | accepted |
| 1.3 | freetype2 latest = paper recipe + harness from freetype2-testing@db8ae87 | Harness moved out of freetype | accepted |
| 1.4 | openssl latest = paper recipe minus `enable-ssl3 enable-ssl3-method`, corpus from fuzz-corpora@e79bbce6 | OpenSSL 4.0 removed SSLv3; corpus became a submodule | accepted |
| 1.5 | gdk-pixbuf latest = meson with options equivalent to the paper's autotools ones | 2.44.8 dropped autotools | accepted |
| 1.6 | bloaty and vorbis latest = HEAD commit; gdk-pixbuf latest = 2.44.8 (not the 2.90 pre-releases) | Their last releases predate the paper's pins / pre-releases excluded | accepted |
| 1.7 | Other latest-row recipe adaptations under the team's pre-decisions (renamed options, out-of-source builds, disabled optional libraries, pinned source builds of missing libraries, mirrors) | Each is labelled in BUILD-INFO and commented in its build.sh | accepted (defaults) |

## 2. Build environment

| # | Drift | Why | Status |
|---|---|---|---|
| 2.1 | Our builder images (Ubuntu 22.04, clang 16, AFL++ 4.32c or 5.03c) instead of FuzzBench's base-builder and UNIFUZZ's zjuchenyuan/afl image | Same recipes and pins, newer toolchain; old images can't build with AFL++ 4.32c/5.03c | accepted (2026-10-25) |
| 2.2 | FuzzBench compile flags applied as FuzzBench does (`-O3`, libc++); `.asan` builds without libc++ | Matches FuzzBench's harness; `.asan` is ours (crash triage) | accepted |
| 2.3 | Seeds rebuilt from each benchmark's recipe (e.g. libjpeg-turbo without testimages, since the original image's path didn't exist; zlib seeds include build products) | Reproduces what FuzzBench actually fed its trials | accepted |
| 2.5 | Toolchain compatibility for old paper versions: clang 16 turns some old warnings into errors (jasper 2.0.12 implicit function declarations; exiv2 0.26's strerror_r config check). Fixed with minimal diagnostic-restoring flags in CC/CXX and configure defines, no source edits | Paper rows are mandatory (team default 9); the code compiled is unchanged | accepted (2026-10-25) |
| 2.6 | MAGMA patches applied with GNU patch 2.7.6 built from a pinned, vendored tarball (no builder image has `patch`; `git apply` was too strict for MAGMA's fuzzy hunks). Same order and bug names as MAGMA's apply_patches.sh | Same tool and diffs as MAGMA | accepted (2026-10-25) |
| 2.6c | MAGMA poppler: AFL++'s libAFLDriver.a kept out of CMake's check-program link flags (the 4.32c/5.03c driver's main needs LLVMFuzzerTestOneInput, which broke every CMake check); still linked into pdf_fuzzer. freetype built `--with-brotli=no` (our builder's cairo pulls in libbrotli, MAGMA's image didn't) | Toolchain compatibility + optional-library rule (c) | accepted (2026-10-25) |
| 2.6b | MAGMA libtiff: library CFLAGS carry an extra `-fPIC` (MAGMA uses it only for magma.o); the harness links system zlib/jpeg/lzma found from `tiffcp`'s dependencies (lzma dynamic, MAGMA static). ffmpeg 4.0.1 `.asan` (triage binary only, not fuzzed) built with `--disable-asm` | No effect on what is fuzzed beyond PIC vs PIE code generation | accepted (2026-10-25) |
| 2.7 | Missing tools/libraries for latest versions built from pinned source: mpg123 1.32.10 (mp3gain 1.6.2), meson 1.5.2 (gdk-pixbuf 2.44.8) | Team default 3 | accepted (default) |
| 2.4 | Format tokens for FuzzBench targets in `g2fuzz/program_to_format.json` (15 entries) chosen by us | Paper gives none for FuzzBench | accepted (2026-10-25) |

## 3. Test harness (our acceptance test only, not the fuzzer)

| # | Drift | Status |
|---|---|---|
| 3.1 | Documented exceptions: zlib (seed floor 30, no "seeds differ"), lcms (floor 40), libpcap (floor 2, its corpus is the `hi` placeholder), freetype2 + bloaty + MAGMA poppler's pdftoppm and pdf_fuzzer (determinism checked with ASLR off; poppler: 5/6 seeds differ by 1 edge with ASLR, 6/6 identical without, jobs 868369/868530; pdfimages deterministic either way), flvmeta (all UNIFUZZ FLV seeds take one 95-edge path), exiv2 (UNIFUZZ jpg seeds have no Exif: exit 253 "No Exif data found", one 527-edge path), gdk-pixbuf-pixdata (exit 1, see 5.1b) | accepted (defaults) |
| 3.2 | `afl-showmap` runs with `AFL_MAP_SIZE=2621440` (FuzzBench's value): 4.32c's showmap aborts on maps > 64K | accepted |

## 4. Fuzzer and code

| # | Drift | Why | Status |
|---|---|---|---|
| 4.1 | AFL++ 4.32c (WORKING, and upstream G2FUZZ) fuzzes with the CmpLog binary instead of the main target (upstream bug, fixed in 5.03c) | So 4.32c vs 5.03c differ by more than "just the version". The paper's own runs likely had it too. Cited in the report as the main caveat on the 4.32c arms | accepted (2026-10-25) |
| 4.2 | Our robustness edits to G2FUZZ, all marked `G2F:` in the code. (a) `py_utils/llm_utils.py`: one shared OpenAI client with a 300 s per-call timeout (`G2F_LLM_TIMEOUT`; upstream sets none, so the SDK default of 600 s with 2 retries applied in the paper) and retries on connection/5xx/429 errors (`G2F_LLM_RETRIES`), plus one JSON line per call in `llm_calls.jsonl` (read by `scripts/fuzz status/results` and `analysis/03-stats.py` for the call counts and latencies in the reports). Phases B and C ran a hand-written loop of 6 attempts with 2-32 s backoff (image `bdb816a-dirty`); simplified on 2026-10-27 to the SDK's own `max_retries` (same timeout, 5 retries), which takes effect at the next image build. (b) `program_gen.py`: three `try/except` blocks so a failed LLM call counts as a failed attempt instead of aborting seed generation. (c) `afl/src/afl-fuzz.c`: `G2F_PLATEAU_SEC`/`G2F_BACKOFF_SEC` env knobs for the LLM-step trigger, 11 lines, defaults identical to upstream's 300 s + 60 s per step; needed because the hook is unconditional, so the AFL++(cmplog) arm sets it to never fire | Local servers fail differently than OpenAI's API; the 300 s limit is ours and is why a thinking model is ruled out (row 5.1) | accepted |
| 4.3 | 5.03c port of G2FUZZ's AFL++ hooks (G2FUZZ-upgradedAFL) | Smoke test + review gauntlet passed | accepted |
| 4.4 | A plain AFL++(cmplog) mode, `scripts/fuzz run <c> <secs> --afl` (both repos), for the paper's baseline fuzzer: same afl-fuzz, no LLM, stock seeds | Paper compares against AFL++(cmplog) | accepted |

## 5. Experiment setup

| # | Drift | Why | Status |
|---|---|---|---|
| 5.1 | Local LLM instead of GPT-3.5/GPT-4: `gpt-oss:120b` (Ollama, `scripts/fuzz` default) or Qwen3.8-27B-FP8 without thinking | No OpenAI; our 300 s per-call timeout (row 4.2; upstream G2FUZZ sets none, so the OpenAI SDK's 600 s applies) rules out thinking models. **Chosen (user, 2026-10-23): Qwen3.8-27B-FP8 without thinking**, after a bake-off vs gpt-oss:120b and llama3:70b (the paper-evaluated family): only Qwen finished seed generation in all 6 runs (20-40 min); gpt-oss had the most seed edges but finished 2/6 in 2h35 (setup/model-bakeoff/) | accepted |
| 5.1b | Non-root sandbox: `gdk-pixbuf-pixdata @@ /dev/null` (UNIFUZZ's args) can't write its temp file next to /dev/null (root-only, as in UNIFUZZ's Docker), so every run exits 1 after parsing; the final save path is never reached. Test accepts exit 1 for it (no ASan report allowed) | Manifest args unchanged (team default 7); parsing, the part being fuzzed, is unaffected | accepted (2026-10-25) |
| 5.2 | Campaigns as Slurm jobs, 2 CPUs / 8 GB each (raised from 4 GB on 2026-10-23: LLM-generated ~10 MB PNG seeds ran out of memory in the pilot), AFL++ output on node-local disk; paper used 64-core Xeon servers | Our cluster | accepted |
| 5.3 | Phase B runs 6 h x 5 reps instead of the paper's 24 h x 5 | Shorter first; the paper's 24 h x 5 is phase C (needs approval) | accepted (2026-10-23) |
| 5.4 | Replication scope: UNIFUZZ (Table 1) first, then MAGMA (Table 3) and FuzzBench | Headline table | accepted (phases A + B approved 2026-10-23) |
| 5.5 | Setup checks before the study: model bake-off, then a 15-min `--test` pilot of all 4 arms (setup/) | Checks the targets, both images and every arm end to end | done (2026-10-23) |
| 5.6 | One Qwen server on a quantumcore A100 for all G2FUZZ campaigns (plus an H100 on gpufairshare if it starts); both G2FUZZ arms of a (program, rep) use the same server | Paper used OpenAI's API; one A100 keeps LLM speed equal across campaigns (an A40 was ~2.5x slower) | accepted (2026-10-23) |
| 5.7 | Two phase B campaigns rerun (fuzzing only, 6 h, their own seeds and generators): `B-ffmpeg-g2432-r3` (seed generation took 3 h, so the job limit cut fuzzing at 5.5 h) and `B-mp42aac-g2503-r3` (an LLM seed timed out in afl-fuzz's start-up check, which aborts AFL++ 4.32c and 5.03c alike; crashing seeds are skipped). They started ~7-10 h after their (program, rep) siblings. The damaged runs stay as `*.damaged-*` and are left out of the analysis. **Fix a (2026-10-24, user-approved):** the mp42aac rerun aborted again on the same seed, so its second attempt runs afl-fuzz with `AFL_IGNORE_SEED_PROBLEMS=1` (a stock AFL++ option: the one timing-out seed is skipped instead of aborting; nothing in G2FUZZ or AFL++ was edited). This campaign is flagged in `results/campaigns.tsv`; `tests-excl-flagged.tsv` repeats the tests without it | Every program keeps 5 full reps per arm | accepted (2026-10-24) |
| 5.9 | Phase C job limits allow 3.5 h of seed generation (`G2F_SEEDGEN_MIN=210`) instead of phase B's 2 h; the paper's seed generation was outside the fuzzing time anyway. Phase C is scoped to the five programs where 6 h was inconclusive, with the 4.32c arms (PLAN.md change 2026-10-25) | 7 of 98 phase B seed generations took over 2 h and one campaign lost 16 min of fuzzing to the limit | accepted (2026-10-25) |
| 5.10 | Bug counts under two triage rules: UNIFUZZ's (ASan report, bug type + top 3 frames) and the same with ASan's allocation cap at 1 GB (`max_allocation_size_mb=1024`), under which an allocation over 1 GB is an `allocation-size-too-big` bug. The fuzzers ran with `afl-fuzz -m 1024`, so they saved such inputs as crashes; most mp42aac crashes are of this kind | Makes the ASan triage see what the fuzzer saw; both counts are reported | accepted (2026-10-25) |
| 5.8 | `B-gdk-pixbuf-pixdata-g2432-r5` is marked OUT_OF_MEMORY by Slurm (one process in the job's 8 GB cgroup was killed once) but afl-fuzz ran the full 6 h, wrote its stats and resume file, and the output was copied back; its execs, corpus and crashes sit among its siblings (r1-r4). Kept as a complete campaign | afl-fuzz's own peak target RSS was 426 MB; the kill hit a child, most likely while decoding a 6.2 MB LLM-generated BMP seed | accepted (2026-10-24) |
| 5.11 | `C-exiv2-afl432-r3` (phase C): AFL++ 4.32c aborted itself at 21 h 53 min (`Incorrect fuzzing setup detected ... 45028 of 45027/45056`, afl-fuzz-stats.c:781). The target corrupted the shared coverage map from 20 h 23 min on (own-binary edges 7.6k -> 45,027 = the full map, queue 4,863 -> 24,018 entries, saved crashes 183 -> 603); the corrupted inputs corrupt the map on the replay binary too (edges_final 55,350 vs 5.6-5.9k for its siblings). Kept, not rerun (user decision 2026-10-26): `complete=short(78796)` in `results/phase-C/campaigns.tsv`; the tests are repeated without it in `results/phase-C/sensitivity-excl-exiv2-afl432-r3/` (exiv2 edges p 0.15 -> 0.016, nothing else changes); its crash triage (604 files, 517 ASan reports, 27 buckets) is valid. A rerun with `AFL_IGNORE_PROBLEMS=1` would only stop the abort, not the corruption | Excluding it strengthens the exiv2 edges result and changes no other conclusion; a 24 h rerun would start a day after its siblings | accepted (2026-10-26) |

## 6. Outside the baseline (for the record)

- exp workspace (BETTER-G2FUZZ-exp): replay-args fix installed (separate study, gauntlet passed).
- LLM-assist study: complete (no effect on the baseline repos).
- README, `scripts/fuzz` shared-server changes: team workflow only, no effect on fuzzing.
