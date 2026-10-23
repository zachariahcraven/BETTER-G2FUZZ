# Drift from the paper's setup

Every place where our setup for the baseline replication differs from what the G2FUZZ authors tested (USENIX Security
2025). WORKING-BETTERG2FUZZ runs AFL++ 4.32c, G2FUZZ-upgradedAFL AFL++ 5.03c; both with a local model.
Status: **accepted** = decided; **review** = still open (the study owner confirms or rejects). Started 2026-10-22.

## 1. Targets and versions

| # | Drift | Why | Status |
|---|---|---|---|
| 1.1 | Latest-release builds for FuzzBench (12 projects) and MAGMA (4) | Paper only fuzzes latest versions for UNIFUZZ (section 5.1.4, Table 4). FuzzBench latest rows are already built; MAGMA latest rows will be **skipped** (default) | review |
| 1.2 | woff2 latest = current OSS-Fuzz build (oss-fuzz@284f6239) | Paper-era recipe can't build woff2 1.0.2 | accepted |
| 1.3 | freetype2 latest = paper recipe + harness from freetype2-testing@db8ae87 | Harness moved out of freetype | accepted |
| 1.4 | openssl latest = paper recipe minus `enable-ssl3 enable-ssl3-method`, corpus from fuzz-corpora@e79bbce6 | OpenSSL 4.0 removed SSLv3; corpus became a submodule | accepted |
| 1.5 | gdk-pixbuf latest = meson with options equivalent to the paper's autotools ones | 2.44.8 dropped autotools | accepted |
| 1.6 | bloaty and vorbis latest = HEAD commit; gdk-pixbuf latest = 2.44.8 (not the 2.90 pre-releases) | Their last releases predate the paper's pins / pre-releases excluded | accepted |
| 1.7 | Other latest-row recipe adaptations under the team's pre-decisions (renamed options, out-of-source builds, disabled optional libraries, pinned source builds of missing libraries, mirrors) | Each is labelled in BUILD-INFO and commented in its build.sh | accepted (defaults) |

## 2. Build environment

| # | Drift | Why | Status |
|---|---|---|---|
| 2.1 | Our builder images (Ubuntu 22.04, clang 16, AFL++ 4.32c or 5.03c) instead of FuzzBench's base-builder and UNIFUZZ's zjuchenyuan/afl image | Same recipes and pins, newer toolchain; old images can't build with AFL++ 4.32c/5.03c | review |
| 2.2 | FuzzBench compile flags applied as FuzzBench does (`-O3`, libc++); `.asan` builds without libc++ | Matches FuzzBench's harness; `.asan` is ours (crash triage) | accepted |
| 2.3 | Seeds rebuilt from each benchmark's recipe (e.g. libjpeg-turbo without testimages, since the original image's path didn't exist; zlib seeds include build products) | Reproduces what FuzzBench actually fed its trials | accepted |
| 2.5 | Toolchain compatibility for old paper versions: clang 16 turns some old warnings into errors (jasper 2.0.12 implicit function declarations; exiv2 0.26's strerror_r config check). Fixed with minimal diagnostic-restoring flags in CC/CXX and configure defines, no source edits | Paper rows are mandatory (team default 9); the code compiled is unchanged | review |
| 2.6 | MAGMA patches applied with GNU patch 2.7.6 built from a pinned, vendored tarball (no builder image has `patch`; `git apply` was too strict for MAGMA's fuzzy hunks). Same order and bug names as MAGMA's apply_patches.sh | Same tool and diffs as MAGMA | review |
| 2.6c | MAGMA poppler: AFL++'s libAFLDriver.a kept out of CMake's check-program link flags (the 4.32c/5.03c driver's main needs LLVMFuzzerTestOneInput, which broke every CMake check); still linked into pdf_fuzzer. freetype built `--with-brotli=no` (our builder's cairo pulls in libbrotli, MAGMA's image didn't) | Toolchain compatibility + optional-library rule (c) | review |
| 2.6b | MAGMA libtiff: library CFLAGS carry an extra `-fPIC` (MAGMA uses it only for magma.o); the harness links system zlib/jpeg/lzma found from `tiffcp`'s dependencies (lzma dynamic, MAGMA static). ffmpeg 4.0.1 `.asan` (triage binary only, not fuzzed) built with `--disable-asm` | No effect on what is fuzzed beyond PIC vs PIE code generation | review |
| 2.7 | Missing tools/libraries for latest versions built from pinned source: mpg123 1.32.10 (mp3gain 1.6.2), meson 1.5.2 (gdk-pixbuf 2.44.8) | Team default 3 | accepted (default) |
| 2.4 | Format tokens for FuzzBench targets in `g2fuzz/program_to_format.json` (15 entries) chosen by us | Paper gives none for FuzzBench | review |

## 3. Test harness (our acceptance test only, not the fuzzer)

| # | Drift | Status |
|---|---|---|
| 3.1 | Documented exceptions: zlib (seed floor 30, no "seeds differ"), lcms (floor 40), libpcap (floor 2, its corpus is the `hi` placeholder), freetype2 + bloaty + MAGMA poppler's pdftoppm and pdf_fuzzer (determinism checked with ASLR off; poppler: 5/6 seeds differ by 1 edge with ASLR, 6/6 identical without, jobs 868369/868530; pdfimages deterministic either way), flvmeta (all UNIFUZZ FLV seeds take one 95-edge path), exiv2 (UNIFUZZ jpg seeds have no Exif: exit 253 "No Exif data found", one 527-edge path), gdk-pixbuf-pixdata (exit 1, see 5.1b) | accepted (defaults) |
| 3.2 | `afl-showmap` runs with `AFL_MAP_SIZE=2621440` (FuzzBench's value): 4.32c's showmap aborts on maps > 64K | accepted |

## 4. Fuzzer and code

| # | Drift | Why | Status |
|---|---|---|---|
| 4.1 | AFL++ 4.32c (WORKING, and upstream G2FUZZ) fuzzes with the CmpLog binary instead of the main target (upstream bug, fixed in 5.03c) | So 4.32c vs 5.03c differ by more than "just the version". The paper's own runs likely had it too | review |
| 4.2 | Our robustness commits to G2FUZZ: LLM timeout/retries/logging, error handling around LLM calls, `G2F_PLATEAU_SEC`/`G2F_BACKOFF_SEC` (defaults equal upstream) | Local servers fail differently than OpenAI's API | accepted |
| 4.3 | 5.03c port of G2FUZZ's AFL++ hooks (G2FUZZ-upgradedAFL) | Smoke test + review gauntlet passed | accepted |
| 4.4 | A plain AFL++(cmplog) mode, `scripts/fuzz run <c> <secs> --afl` (both repos), for the paper's baseline fuzzer: same afl-fuzz, no LLM, stock seeds | Paper compares against AFL++(cmplog) | accepted |

## 5. Experiment setup

| # | Drift | Why | Status |
|---|---|---|---|
| 5.1 | Local LLM instead of GPT-3.5/GPT-4: `gpt-oss:120b` (Ollama, `scripts/fuzz` default) or Qwen3.8-27B-FP8 without thinking | No OpenAI; G2FUZZ's 300 s client timeout rules out thinking models. **Chosen (user, 2026-10-23): Qwen3.8-27B-FP8 without thinking**, after a bake-off vs gpt-oss:120b and llama3:70b (the paper-evaluated family): only Qwen finished seed generation in all 6 runs (20-40 min); gpt-oss had the most seed edges but finished 2/6 in 2h35 (setup/model-bakeoff/) | accepted |
| 5.1b | Non-root sandbox: `gdk-pixbuf-pixdata @@ /dev/null` (UNIFUZZ's args) can't write its temp file next to /dev/null (root-only, as in UNIFUZZ's Docker), so every run exits 1 after parsing; the final save path is never reached. Test accepts exit 1 for it (no ASan report allowed) | Manifest args unchanged (team default 7); parsing, the part being fuzzed, is unaffected | review |
| 5.2 | Campaigns as Slurm jobs, 2 CPUs / 8 GB each (raised from 4 GB on 2026-10-23: LLM-generated ~10 MB PNG seeds ran out of memory in the pilot), AFL++ output on node-local disk; paper used 64-core Xeon servers | Our cluster | accepted |
| 5.3 | Phase B runs 6 h x 5 reps instead of the paper's 24 h x 5 | Shorter first; the paper's 24 h x 5 is phase C (needs approval) | accepted (2026-10-23) |
| 5.4 | Replication scope: UNIFUZZ (Table 1) first, then MAGMA (Table 3) and FuzzBench | Headline table | accepted (phases A + B approved 2026-10-23) |
| 5.5 | Setup checks before the study: model bake-off, then a 15-min `--test` pilot of all 4 arms (setup/) | Checks the targets, both images and every arm end to end | done (2026-10-23) |
| 5.6 | One Qwen server on a quantumcore A100 for all G2FUZZ campaigns (plus an H100 on gpufairshare if it starts); both G2FUZZ arms of a (program, rep) use the same server | Paper used OpenAI's API; one A100 keeps LLM speed equal across campaigns (an A40 was ~2.5x slower) | accepted (2026-10-23) |

## 6. Outside the baseline (for the record)

- exp workspace (BETTER-G2FUZZ-exp): replay-args fix installed (separate study, gauntlet passed).
- LLM-assist study: complete (no effect on the baseline repos).
- README, `scripts/fuzz` shared-server changes: team workflow only, no effect on fuzzing.
