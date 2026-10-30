# 03 Model sweep on quantumcore

**Question:** [02](../02-model-sweep/README.md)'s: how much does the choice of LLM change what G2FUZZ finds on 15 of
the paper's targets, and does any model beat plain AFL++? Run on the quantumcore group's resources so the class's
stay free; 02 stays empty.
**Owner:** n59m742. **Status:** planned. **Started:** 2026-10-30.

## Design
- **Arms:** eight models, one per family, served on one H100 each:
  - Qwen3.8-27B-FP8 (Alibaba), Llama-3.1-8B-Instruct (Meta, the paper's §5.5 family) and DeepSeek-Coder-V2-Lite (code,
    MoE) in round 1, with gpt-oss-20b (OpenAI's open MoE);
  - gemma-4-31B-it (Google), phi-4 (Microsoft), Mistral-Small-3.1-24B and Seed-Coder-8B (ByteDance, code) in round 2;
  - plus `afl`, plain AFL++ (cmplog) from the stock seeds: the no-LLM baseline.
- **Runs:** the 15 targets in `launch/targets.txt` (02's), **5 reps** per model and target, 6 h of fuzzing each, the
  `ucb` generator scheduler: 675 campaigns.
- **Where:** `launch/study.conf` sets `gpu = qc-h100`, `account = priority-quantumcore`, `partition = priority`.
  - The account allows 4 GPUs, so servers start in arm order, four at a time.
  - Each round mixes a large dense model, a small one, a code model and a mixture-of-experts one.
  - Campaigns (2 CPUs, 8 GB each) run on the `priority` CPU nodes (EPYC 7H12).
- **Code:** two fixes made for this study (2026-10-30), both differences from upstream G2FUZZ and from 01:
  1. **UCB bookkeeping** (`generator_scheduler.py`): the snapshot holds every generator, not only one format's.
  2. **`pip_debug`** (`func.py`): a malformed pip answer is asked for again instead of run as a command.
- **Dropped: starcoder2-15b-instruct.** Its model card says it is "designed to respond to coding-related instructions
  in a single turn" and "might not adhere strictly to instructions that dictate the output format". In the
  2026-10-30 jhead trial it answered G2FUZZ's format question with code, looped to its 16K limit, and made no seeds.

## Analysis plan (fixed before launch)
- **Metric:**
  - `edges` from `fuzzer_stats` while it runs.
  - For the report: coverage replayed as in `01-baseline-replication/analysis`, at 6 h and over time.
  - The t=0 coverage of each campaign's `initial_seeds` separates seed generation from fuzzing.
- **Tests:**
  - Per target, the median of the 5 reps.
  - Models ranked per target; Friedman test over the 15 targets (ties share a rank), then Nemenyi.
  - Each model against `afl` per target: Mann–Whitney U and Vargha–Delaney A12.
- **`no seeds` cells:** seed generation ran and the model answered, but made no seeds, so the campaign doesn't fuzz
  (`scripts/fuzz` stops; upstream would fuzz the stock seeds).
  - Such cells are kept, and models that fail on the same target tie for last place there.
  - Seed-generation success is reported per model as a metric of its own.
  - A sensitivity analysis repeats the tests on only the targets where every model made seeds.
- **Failures:**
  - A `failed` or `done (short)` campaign is run again once (`--retry-failed`); its first run stays in
    `campaigns/.retried/`.
  - A campaign that fails twice is excluded and listed.
- **Pinned:**
  - Everything else: the image (its commit), vLLM 0.31.0 (`shared-models/containers`), the weights' revisions
    (`shared-models/REVISIONS.txt` or each model's `.cache` metadata), and G2FUZZ's temperatures.
  - Context: 32K, except phi-4's 16K.
  - Chat templates: each model's own, with Qwen's thinking off.

## Running it
On Tempest, from the repo root (members of `priority-quantumcore` only, with that group's OK):

```bash
scripts/study start 03-model-sweep-qc --servers --dry          # check; changes nothing
scripts/study start 03-model-sweep-qc --servers --background   # run it all (one 1-CPU driver job)
scripts/study status 03-model-sweep-qc                         # progress, other users' jobs, failures and why
```
- **Failed or cut-short campaigns:** add `--retry-failed` to the run command (a running driver relaunches them).
- **The study gave up on a model's server:** add `--retry-servers`.
- **The quantumcore group needs its resources:** `scancel -u $USER -A priority-quantumcore`. Later: the run command plus
  `--retry-failed`.
- **Results:** the driver writes `results/<model>-r1-5.csv` as each model finishes.
- **Before the first run:** `start` refuses an image that doesn't hold this checkout's code. After committing and
  pushing, run `scripts/tempest-image` from a Mac.
- **Time:** about 2.5 days with all of `priority-quantumcore`. The limit is the account's memory (1 TB), about 95
  campaigns at once next to 4 servers. If the group uses part of it, longer: about 4–5 days at half.
  - It also needs free H100s: the account's 4 is a cap, not a reservation.
  - Two of the four H100 nodes are reserved (`catchat`), and other groups' `gpufairshare` jobs on the other two can't
    be preempted, so a server can wait hours. On 2026-10-30 afternoon all 8 were taken for about 8 h.
- **Preemption:**
  - These jobs requeue other users' `gpuunsafe` and `unsafe` jobs, but never `fairshare` or priority jobs.
  - gpu055 and gpu057 are in the `catchat` reservation until 2027-08-12.

## Known limitations (recorded, not changed)
- **It mostly measures seed generation.**
  - LLM mutation steps only follow a 300 s plateau: 01 had 293 in 100 campaigns, and none in the 20-min trial.
  - In the paper's ablation (Table 13), mutation added little on jhead, imginfo and gdk-pixbuf-pixdata.
  - Multi-format targets skip G2FUZZ's rare-feature mutation.
- **6 h, not 24 h:** the paper's Fuzztruction comparison also ran 6 h × 5, and its Table 19 shows no median change
  between 23 h and 23 h 45 min. Coverage over time is plotted.
- **Context:**
  - phi-4 is served at 16K, the others at 32K.
  - No `max_tokens` is set (as upstream), so answers can run to the limit.
  - `llm_400` and `llm_cut` count both effects.
- **Sampling:**
  - G2FUZZ sets the temperature (0.7 or 0.2). Mistral's card recommends 0.15.
  - vLLM adds each model's own `generation_config.json`: Qwen top_k 20 / top_p 0.95, DeepSeek top_p 0.95, gemma
    top_k 64 / top_p 0.95, the others none.
- **Reasoning:**
  - Qwen runs with thinking off.
  - gpt-oss reasons at its default effort, hidden from G2FUZZ (it gets only the answer). Neither is varied.
- **Hardware:** everything runs on H100s, so Mistral runs in bf16 (fp8 on an A40). The CPUs differ from 01's
  (EPYC 9684X), and the nodes are shared, so execs/s and edges compare within this study only.
- **Rounds:** round 2 runs a day later than round 1, on the same partitions. `afl` runs in round 1 only.
- **Scope:** the results are G2FUZZ with our UCB scheduler. The paper never ran an open model, so there are no
  paper numbers for these.
- **Training data:** the targets are old, so the models may have seen their formats or code.
- **MAGMA canaries** are off during campaigns: known bugs for libpng_read_fuzzer and sndfile_fuzzer need a replay.

## Results
Filled in when the study ends.
