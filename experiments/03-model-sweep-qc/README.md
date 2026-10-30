# 03 Model sweep on quantumcore

**Question:** [02](../02-model-sweep/README.md)'s, with 02's design and targets: how much does the choice of LLM
change what G2FUZZ finds? Run on the quantumcore group's resources so the class's stay free; 02 stays empty.
**Owner:** n59m742. **Status:** planned. **Started:** 2026-10-30.

## How it differs from 02
- **Where it runs:** `launch/study.conf` is 02's plus `gpu = qc-h100`, `account = priority-quantumcore`,
  `partition = priority`. Each model's server gets one H100 (`gpupriority`). The driver and campaigns run on the
  `priority` CPU nodes (EPYC 7H12). The account allows 4 GPUs for the whole group, so the fifth server waits
  (`AssocGrpGRES`) until a model finishes. Nothing runs on the class accounts.
- **Code:** two fixes made for this study (2026-10-30), both differences from upstream G2FUZZ and from 01:
  1. **UCB bookkeeping** (`g2fuzz/py_utils/generator_scheduler.py`). Its snapshot now holds every generator, not
     only the format of the current pattern step. Before the fix, on multi-format targets (jhead,
     gdk-pixbuf-pixdata, imginfo, sndfile_fuzzer), other formats' generators were credited as children, failed
     steps weren't counted, and a whole format could be excluded for good.
  2. **`pip_debug`** (`g2fuzz/py_utils/func.py`). A malformed pip answer is now asked for again instead of being
     run as a command.
- **`no seeds` cells:** seed generation ran and the model answered, but no seeds came out, so G2FUZZ doesn't fuzz.
  These cells are kept, ranked last for that target, and counted per model. In the 2026-10-30 trial, starcoder2 did
  this on jhead within 4 min: it answered with code instead of the asked-for list, then looped to its 16K limit.
  Expect most of its cells to look like that.

## Running it
On Tempest, from the repo root (members of `priority-quantumcore` only, with that group's OK):

```bash
scripts/study start 03-model-sweep-qc --servers --dry          # check; changes nothing
scripts/study start 03-model-sweep-qc --servers --background   # run it all (one 1-CPU driver job)
scripts/study status 03-model-sweep-qc                         # progress, other users' jobs, failures and why
```
- **Failed or cut-short campaigns:** add `--retry-failed` to the run command. A running driver relaunches them.
- **The study gave up on a model's server:** add `--retry-servers`.
- **The quantumcore group needs its GPUs:** `scancel -u $USER -A priority-quantumcore`. Later: the run command plus
  `--retry-failed`.
- **Results:** the driver writes `results/<model>-r1.csv` as each model finishes.
- **Before the first run:** `start` refuses an image that doesn't hold this checkout's code. After committing and
  pushing, run `scripts/tempest-image` from a Mac.
- **Time:** about 20–28 h (about 10 h per model; the fifth starts after the first four).
- **Preemption:**
  - These jobs requeue other users' `gpuunsafe` and `unsafe` jobs, but never `fairshare` or priority jobs.
  - gpu055 and gpu057 are in the `catchat` reservation until 2027-08-12.

## Known limitations (recorded, not changed)
- **Context:** phi-4 and starcoder2 are served at 16K tokens (their limit), the others at 32K. Over-long prompts
  fail (`llm_400`) and long answers are cut off (`llm_cut`): part of what is compared.
- **Sampling:** G2FUZZ sets the temperature. vLLM adds each model's own `generation_config.json` (in
  `shared-models/<model>/`): Qwen top_k 20 / top_p 0.95, DeepSeek top_p 0.95, the others none.
- **Hardware:** everything runs on H100s, so Mistral runs in bf16 (fp8 on an A40). The CPUs differ from 01's
  (EPYC 9684X), so execs/s and edges compare within this study only.
- **One rep per cell:** compare models across the 15 targets (ranks, Friedman test), with 01's rep-to-rep spread as
  the noise floor.
- **Fuzzing time:** LLM mutation steps run inside the 6 h `-V` budget, so a model with faster LLM steps gets more
  fuzzing. The fifth model also runs later, with other jobs on the nodes.
- **MAGMA canaries** are off during campaigns: known bugs for libpng_read_fuzzer and sndfile_fuzzer need a replay.

## Results
Filled in when the study ends. `edges` come from AFL++'s `fuzzer_stats` (fine for comparing models on one target);
for the report, replay the queues as in `01-baseline-replication/analysis`.
