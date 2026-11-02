# 04 Model sweep on quantumcore, 24 h

**Question:** [03](../03-model-sweep-qc/README.md)'s, at the paper's length: 24 h of fuzzing per campaign instead
of 6 h. Do 03's ranking of the models, and how they compare with plain AFL++, still hold at 24 h?
**Owner:** n59m742. **Status:** running (launched 2026-11-01 23:43, when 03's driver ended, by starter job 992371;
driver job 993456). **Started:** 2026-11-01.

## Design
- **Two differences from 03:** the time, `secs = 86400` (03: 21600), and where AFL++ writes its output,
  `output = campaign` (below). Arms, targets, reps, image, servers and accounts are 03's.
- **Arms:** eight models, one per family, served on one H100 each:
  - Qwen3.8-27B-FP8 (Alibaba), Llama-3.1-8B-Instruct (Meta, the paper's §5.5 family) and DeepSeek-Coder-V2-Lite (code,
    MoE) in round 1, with gpt-oss-20b (OpenAI's open MoE);
  - gemma-4-31B-it (Google), phi-4 (Microsoft), Mistral-Small-3.1-24B and Seed-Coder-8B (ByteDance, code) in round 2;
  - plus `afl`, plain AFL++ (cmplog) from the stock seeds: the no-LLM baseline.
- **Runs:** the 15 targets in `launch/targets.txt` (02's), **5 reps** per model and target, 24 h of fuzzing each, the
  `ucb` generator scheduler: 675 campaigns.
- **Where:** `launch/study.conf` sets `gpu = qc-h100`, `account = priority-quantumcore`, `partition = priority`.
  - The account allows 4 GPUs, so servers start in arm order, four at a time.
  - Each round mixes a large dense model, a small one, a code model and a mixture-of-experts one.
  - Campaigns (2 CPUs, 8 GB each) run on the `priority` CPU nodes (EPYC 7H12).
- **Code:** two fixes made for 03 (2026-10-30), both differences from upstream G2FUZZ and from 01:
  1. **UCB bookkeeping** (`generator_scheduler.py`): the snapshot holds every generator, not only one format's.
  2. **`pip_debug`** (`func.py`): a malformed pip answer is asked for again instead of run as a command.
- **AFL++ output in the campaign folders** (`output = campaign`, added 2026-11-01, before launch). 03 wrote it to the
  node's local disk and copied it to the campaign folder every 30 s. 04 writes it straight into the campaign folder on
  the group's storage. The file the target reads (`.cur_input`, rewritten for every execution) goes to the job's
  memory folder (`AFL_TMPDIR`, a few MB of the 8 GB).
  - Why: the node disks are shared with other users' jobs. During 03 they filled up 23 times by 16:33 on 2026-11-01,
    and each fill stopped every campaign on that node: 73 stops
    ([OURS-3](../../docs/KNOWN_BUGS.md#ours-3-output-on-the-nodes-shared-disk)). At 03's rate since the fills began
    (one stop per 8.5 campaign-hours), only 6% of 24 h campaigns would finish uninterrupted, and 04 would take 2.4–5.6
    times as long.
  - Test (2026-11-01, epyc010, both settings side by side, 45 min each; the campaigns are in
    `experiments/practice/campaigns/n59m742-out-*`):
    - Plain AFL++ ran as fast either way: libpcap_fuzz_both 6.56 M executions on average with the node disk and
      6.53 M with the campaign folder. tiffsplit ran 3.00 M and 2.88 M; its two campaign-folder runs were the
      slowest and the fastest of the four. Edges stayed within each target's spread.
    - A G2FUZZ pair (phi-4's lcms seeds and generators from 03) ran its in-run generators and an LLM step with the
      campaign folder. Its edges, 1,304 and 639, match the two levels 03's phi-4 lcms runs reach at 45 min
      (1,280–1,352 or 611–636).
- **Dropped: starcoder2-15b-instruct.** Its model card says it is "designed to respond to coding-related instructions
  in a single turn" and "might not adhere strictly to instructions that dictate the output format". In the
  2026-10-30 jhead trial it answered G2FUZZ's format question with code, looped to its 16K limit, and made no seeds.

## Analysis plan (fixed before launch)
- **Metric:**
  - `edges` from `fuzzer_stats` while it runs.
  - For the report: coverage replayed as in `01-baseline-replication/analysis`, at 24 h, at 6 h (03's length, to
    compare the two studies) and over time.
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
scripts/study start 04-model-sweep-qc-24h --servers --dry          # check; changes nothing
scripts/study start 04-model-sweep-qc-24h --servers --background   # run it all (one 1-CPU driver job)
scripts/study status 04-model-sweep-qc-24h                         # progress, other users' jobs, failures and why
```
- **Failed or cut-short campaigns:** add `--retry-failed` to the run command (a running driver relaunches them).
- **The study gave up on a model's server:** add `--retry-servers`.
- **The quantumcore group needs its resources:** `scancel -u $USER -A priority-quantumcore`. Later: the run command plus
  `--retry-failed`.
- **Results:** the driver writes `results/<model>-r1-5.csv` as each model finishes.
- **Before the first run:** `start` refuses an image that doesn't hold this checkout's code. After committing and
  pushing, run `scripts/tempest-image` from a Mac.
- **How it was run:** not with `scripts/study` itself but with n59m742's private copy of it (`~/g2f-04-driver/study`,
  sha1 2780096, not in the repo: partners have no quantumcore). It is 03's (`~/g2f-03-driver/study`, sha1 4866acf)
  plus the `output` setting from this repo's `scripts/study`. That is `scripts/study` of ce0b2bb plus one addition:
  when quantumcore's CPUs or memory are full, campaigns also launch on the class priority account
  (`priority-csci-591-automated-vulnerability-discovery`, the same `priority` partition and EPYC 7H12 nodes), at most
  120 at once (03: 64). Partners had no plans for that account (2026-11-01), and 120 leaves room for one of their
  servers (8 CPUs, 64 GB).
  - Those campaigns use the same quantumcore H100 servers: the driver passes them the server's address.
  - Each campaign's `launch.txt` names its account. The 4-at-once seed-generation limit counts both accounts.
  - Command: `STUDY_DRIVER_DAYS=14 STUDY_EXTRA_ACCOUNT=priority-csci-591-automated-vulnerability-discovery
    STUDY_EXTRA_MAX=120 ~/g2f-04-driver/study start 04-model-sweep-qc-24h --servers --background`, run by a Slurm job
    (992371) that waits for 03's driver (job 972064) to end successfully.
- **Time:** about 4–5 days with all of `priority-quantumcore` and up to 120 campaigns on the class account (5–6 days
  at 03's 64). The limit is the accounts' memory (1 TB each): about 95 campaigns at once on quantumcore next to 4
  servers. If the group uses part of it, longer. Full node disks shouldn't stop campaigns now (`output = campaign`,
  above). The driver may run 14 days (`STUDY_DRIVER_DAYS=14`; the default is 7).
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
- **24 h, the paper's length:** 03 is the same design at 6 h.
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
- **Rounds:** round 2 runs about 2.5 days later than round 1, on the same partitions. `afl` runs in round 1 only.
- **Scope:** the results are G2FUZZ with our UCB scheduler. The paper never ran an open model, so there are no
  paper numbers for these.
- **Training data:** the targets are old, so the models may have seen their formats or code.
- **MAGMA canaries** are off during campaigns: known bugs for libpng_read_fuzzer and sndfile_fuzzer need a replay.
- **afl-fuzz crashes** (upstream G2FUZZ bugs [G2F-1](../../docs/KNOWN_BUGS.md#g2f-1-in-run-seeds-skip-afls-size-checks) and [G2F-3](../../docs/KNOWN_BUGS.md#g2f-3-afl-fuzz-heap-corruption-in-g2fuzz-runs), found in 03): kept, since G2FUZZ's
  code is 03's. At 24 h there are more LLM steps, so likely more crashes. Each crashed campaign is run again
  once, and the tests are also repeated with crashed runs kept at their coverage before the crash. Other bugs:
  [docs/KNOWN_BUGS.md](../../docs/KNOWN_BUGS.md).
- **Full node disk** ([OURS-3](../../docs/KNOWN_BUGS.md#ours-3-output-on-the-nodes-shared-disk), found in 03):
  avoided by `output = campaign` (Design). The target's and the generators' temp files are still in the node's `/tmp`.
  A campaign stopped by a full disk anyway would be run again and not count toward the two-failure limit.
  - Putting all of AFL++'s output in memory (`/dev/shm`) was considered (2026-11-01) and not done. Those files count
    against each campaign's 8 GB, which can't grow without fewer campaigns running at once.
  - With the output elsewhere than 03's, execs/s compare within this study only (as above, for the shared nodes).

## Results
Filled in when the study ends.
