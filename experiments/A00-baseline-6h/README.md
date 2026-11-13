# A00-baseline-6h

**Question:** what does Alfred reach in 6 h on 03–05's 15 targets, next to plain AFL++ 5.03c, and does running the LLM
worker's steps more often (continuous, or a shorter stall) help?
**Owner:** n59m742. **Status:** planned (after study 05 frees the compute, about 2026-11-13). **Started:** –

## Design
- Round A00 of [docs/ALFRED-ROUNDS.md](../../docs/ALFRED-ROUNDS.md): its acceptance rule decides the switches.
- **Arms** (`launch/study.conf`):
  - `control`: Alfred's defaults: a step after 300 s without a find, plus 60 s per step, as upstream.
  - `afl`: AFL++ 5.03c with CmpLog, no LLM, from the stock seeds. This is the baseline, with no decision.
  - `continuous`: `G2F_LLM_MODE=continuous`, one LLM step after another.
  - `fast-stall`: a step after 120 s without a find, with no backoff.
- **Why the timing arms:** Alfred's worker runs beside afl-fuzz instead of pausing it. More steps cost GPU time, not
  fuzzing time.
- **Targets and runs:**
  - The 15 targets of 03–05 (`launch/targets.txt`).
  - 5 reps of 6 h each, on gpt-oss-20b. It was the best model in 03 and 04.
  - Seeds are shared: one seed generation per target, used by all three G2FUZZ arms.
  - That makes 300 campaigns plus 15 seed campaigns.
- **Where:**
  - Campaigns: `priority-quantumcore`, with the class priority account as the extra account (`STUDY_EXTRA_ACCOUNT`).
  - The server runs on `qc-h100`.
  - AFL++ output goes into the campaign folders.
- **Image and targets:** Alfred's `build/g2fuzz.sif` (its commit is in each `launch.txt`), with the targets rebuilt
  for 5.03c in `g2f-targets-alfred/paper`.
- **Also a bug check, read from each campaign's files:**
  - G2F-1: no queue file over 1 MiB.
  - G2F-3: no heap errors in G2FUZZ arms, including vorbis.
  - OURS-4: libpcap runs with 16G.
  - Worker tracebacks.
- **Before launch:**
  - Set `scheduler` from 05's result: `random` (2026-11-12, docs/ALFRED-ROUNDS.md, Rounds log).
  - Rebuild the targets.
  - Run `scripts/study show A00-baseline-6h`.

## Running it
```bash
STUDY_EXTRA_ACCOUNT=priority-csci-591-automated-vulnerability-discovery STUDY_EXTRA_MAX=120 \
  scripts/study start A00-baseline-6h --servers --background
scripts/study status A00-baseline-6h
# when it ends:
scripts/study results A00-baseline-6h && scripts/compare A00-baseline-6h && scripts/lineage A00-baseline-6h
```

## Results
Filled in when the round ends. The decision goes in `docs/ALFRED-ROUNDS.md`.
