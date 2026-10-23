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
  generations at a time (longer queues push calls past G2FUZZ's 300 s limit). If the queued gpufairshare H100 server
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
- 2026-10-23: model = Qwen3.8-27B-FP8-nothink after the bake-off ([setup/model-bakeoff](setup/model-bakeoff/)).
- 2026-10-23: LLM servers only on the quantumcore account; the class GPU account is left to teammates.
- 2026-10-23: 8 GB per campaign for all four arms (the pilot's 4 GB ran out of memory on ~10 MB LLM PNG seeds).
- 2026-10-23: phase B on the A100 only (+ H100 if it starts); an A40 was ~2.5x slower per call, which would let LLM
  speed differ between campaigns.
- 2026-10-23: phase B 6 h x 5 instead of 24 h x 5 (shorter first); 24 h is phase C.
