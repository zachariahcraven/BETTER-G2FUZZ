# 01 Baseline replication: plan

Approved 2026-10-23 (setup + phase B). Phase C needs its own approval.

## What the paper did (G2FUZZ, USENIX Security 2025)
- **UNIFUZZ (Table 1):** 10 programs (exiv2, gdk-pixbuf-pixdata, imginfo, jhead, tiffsplit, mp3gain, ffmpeg, flvmeta,
  mp42aac, pdftotext), 24 h x 5 runs, G2FUZZ (GPT-3.5/GPT-4) vs AFL++ cmplog/fast/mopt/rare. Metrics: edges, unique
  bugs (ASan, top 3 frames). G2FUZZ best on 9 of 10 programs; AFL++(cmplog) the strongest baseline.
- **MAGMA (Table 3):** CVEs triggered. **FuzzBench:** 23 h trials. **Latest versions (Table 4):** new bugs.
- Same stock seeds for every fuzzer; G2FUZZ's fuzzing pauses during its seed generation.

## Design
- **Arms:** `g2432`, `afl432` (WORKING, AFL++ 4.32c), `g2503`, `afl503` (G2FUZZ-upgradedAFL, AFL++ 5.03c), all on
  the paper-version targets (`g2f-targets/paper`, `g2f-targets/afl503/paper`). AFL++ fast/mopt/rare are left out.
- **Claim tested:** G2FUZZ > AFL++(cmplog) per program. AFL++ 4.32c vs 5.03c comes for free.
- **Phase B:** UNIFUZZ, 6 h x 5 reps, 200 campaigns (1,200 campaign-hours) + 100 seed generations.
- **Phase C (approval needed):** the paper's 24 h x 5 on UNIFUZZ, then MAGMA and FuzzBench.

## Fairness
- All 4 arms of a (program, rep) start together. Seeds: AFL arms = stock seeds; G2FUZZ arms = stock + their own LLM
  seeds. Seed generation is outside the fuzzing time (`scripts/fuzz` runs it before `afl-fuzz -V`), as in the paper.
- **LLM:** `Qwen3.8-27B-FP8-nothink` (vLLM) on ONE quantumcore A100 for every G2FUZZ campaign, at most ~10 seed
  generations at a time (longer queues push calls past our 300 s per-call limit (DRIFT 4.2)). If the queued gpufairshare H100 server
  starts, new (program, rep) groups may use it; both G2FUZZ arms of a group always share a server, and each campaign
  records its server.
- **Resources:** each campaign 2 CPUs, 8 GB, `fairshare` partition, class account; at most ~60 campaigns at once.

## Measurements and analysis
- **Edges:** every final queue of every arm replayed on ONE common binary (the 4.32c tree's `.afl`, `afl-showmap`,
  `AFL_MAP_SIZE=2621440`), since edge IDs differ between AFL++ versions and builds.
- **Unique bugs:** crashes rerun on `.asan`, deduplicated by the top 3 ASan frames (UNIFUZZ's rule, as the paper).
- Also execs/s, LLM steps, LLM calls and latency, to separate throughput from search effects.
- **Per program:** median + IQR, Mann-Whitney U and Vargha-Delaney A12 (G2FUZZ vs AFL per AFL++ version; 4.32c vs
  5.03c). **Replication criterion:** the sign agrees with Table 1 on most of the 10 programs; absolute numbers are not
  expected to match (hardware, local LLM, toolchain).
- MAGMA later: needs a post-hoc replay with a canary store and MAGMA's monitor; designed before phase C.

## Changes (dated)
- 2026-10-23: model = Qwen3.8-27B-FP8-nothink after the bake-off ([setup/](setup/README.md#model-bake-off-2026-10-23)).
- 2026-10-23: LLM servers only on the quantumcore account; the class GPU account is left to teammates.
- 2026-10-23: 8 GB per campaign for all four arms (the pilot's 4 GB ran out of memory on ~10 MB LLM PNG seeds).
- 2026-10-23: phase B on the A100 only (+ H100 if it starts); an A40 was ~2.5x slower per call, which would let LLM
  speed differ between campaigns.
- 2026-10-23: phase B 6 h x 5 instead of 24 h x 5 (shorter first); 24 h is phase C.
- 2026-10-24: two damaged campaigns rerun, fuzzing only with their own seeds (`launch/rerun-damaged.sh`, DRIFT.md 5.7).
- 2026-10-24: the mp42aac rerun aborted again on its timing-out LLM seed; second attempt with `AFL_IGNORE_SEED_PROBLEMS=1`
  for that one campaign (DRIFT.md 5.7, flagged in the results; tests repeated without it). The OOM-flagged
  `B-gdk-pixbuf-pixdata-g2432-r5` is kept (DRIFT.md 5.8).
- 2026-10-24: analysis written (`analysis/README.md`). Its Slurm arrays may run on the `priority` partition
  (quantumcore account): node type does not affect edge or crash counts, and `fairshare` stalled for ~8 h that day.
- 2026-10-25 (user-approved): phase C scoped to where 6 h was inconclusive: 24 h x 5 on exiv2, gdk-pixbuf-pixdata,
  imginfo, jhead, mp3gain, AFL++ 4.32c arms only (`launch/phaseC.sh`, 50 campaigns, 1,200 campaign-hours). The four
  programs already significant at 6 h and the saturated flvmeta keep their phase B result; the 5.03c arms are not
  repeated. Same allocation as phase B: campaign CPUs on `fairshare` under the class group account, the LLM on a
  quantumcore A100, an H100 on gpufairshare only if the queue gives one; the class priority account stays free.
- 2026-10-25: before phase C, two wrapper changes (no G2FUZZ/AFL++ code): `scripts/fuzz` stops afl-fuzz by PID (the
  image has no pkill; `exec afl-fuzz` in the generated run.sh) and `G2F_SEEDGEN_MIN` sets the seed-generation
  allowance in the job limit (phase C uses 210 min; DRIFT.md 5.9).
- 2026-10-25: second crash-triage rule reported next to UNIFUZZ's: ASan allocation cap at 1 GB (DRIFT.md 5.10).
  `B-ffmpeg-g2503-r5` (5 h 44 min) stays as a flagged run; no rerun.
