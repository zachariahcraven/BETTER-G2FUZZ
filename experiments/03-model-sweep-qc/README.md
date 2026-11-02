# 03 Model sweep on quantumcore

**Question:** [02](../02-model-sweep/README.md)'s: how much does the choice of LLM change what G2FUZZ finds on 15 of
the paper's targets, and does any model beat plain AFL++? Run on the quantumcore group's resources so the class's
stay free; 02 stays empty.
**Owner:** n59m742. **Status:** campaigns finished; analysis to do (launched 2026-10-30 19:24; driver job 972064
ended 2026-11-01 23:43, all 675 finished). **Started:** 2026-10-30.

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
- **How it was run:** not with `scripts/study` itself but with n59m742's private copy of it (`~/g2f-03-driver/study`,
  sha1 4866acf, not in the repo: partners have no quantumcore). It is `scripts/study` of ce0b2bb plus one addition:
  when quantumcore's CPUs or memory are full, campaigns also launch on the class priority account
  (`priority-csci-591-automated-vulnerability-discovery`, the same `priority` partition and EPYC 7H12 nodes), at most
  64 at once (half that account, so partners' servers still fit).
  - Those campaigns use the same quantumcore H100 servers: the driver passes them the server's address.
  - Each campaign's `launch.txt` names its account. The 4-at-once seed-generation limit counts both accounts.
  - Command: `STUDY_EXTRA_ACCOUNT=priority-csci-591-automated-vulnerability-discovery STUDY_EXTRA_MAX=64
    ~/g2f-03-driver/study start 03-model-sweep-qc --servers --background`
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
  - gemma-4-31B-it runs in fp8: its bf16 weights (62 GB) leave an 80 GB H100 8.6 GiB of KV cache, less than one 32K
    request needs (15.8 GiB), so its bf16 server didn't start (2026-10-30 trial). Qwen is an FP8 checkpoint too.
- **Rounds:** round 2 runs a day later than round 1, on the same partitions. `afl` runs in round 1 only.
- **Scope:** the results are G2FUZZ with our UCB scheduler. The paper never ran an open model, so there are no
  paper numbers for these.
- **Training data:** the targets are old, so the models may have seen their formats or code.
- **MAGMA canaries** are off during campaigns: known bugs for libpng_read_fuzzer and sndfile_fuzzer need a replay.
- **afl-fuzz crashes** (upstream G2FUZZ bugs [G2F-1](../../docs/KNOWN_BUGS.md#g2f-1-in-run-seeds-skip-afls-size-checks) and [G2F-3](../../docs/KNOWN_BUGS.md#g2f-3-afl-fuzz-heap-corruption-in-g2fuzz-runs), found during the run on 2026-10-31
  and 2026-11-01): files a generator writes while fuzzing skip AFL++'s size checks, and afl-fuzz segfaults on ones
  over 1 MiB (G2F-1); separately, glibc stops afl-fuzz on a corrupted heap (G2F-3, cause not found). Only G2FUZZ arms
  are affected. Campaigns of several models stopped early (listed there). Each is run again once, as above. Not fixed
  mid-study. Most G2F-3 stops come as afl-fuzz exits after the full 6 h; those campaigns count as done.
  - Added after launch: the tests are also repeated with crashed runs kept at their coverage before the crash.
  - Other bugs in the code this study runs, such as AFL++ 4.32c fuzzing the CmpLog binary:
    [docs/KNOWN_BUGS.md](../../docs/KNOWN_BUGS.md).
- **Full node disk** ([OURS-3](../../docs/KNOWN_BUGS.md#ours-3-output-on-the-nodes-shared-disk), 2026-11-01): AFL++'s
  output is on the node's local disk, which other users' jobs share. When it filled, every campaign on that node
  stopped (73 stops on eleven nodes by 16:40). Added after launch: these are run again (46, from 10:40, with the same
  setup), and since the stop isn't a crash it doesn't count toward the two-failure limit.

## Results
Filled in when the study ends.
