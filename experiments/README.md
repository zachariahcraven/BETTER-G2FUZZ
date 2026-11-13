# Experiments

Every campaign lives here. A study is one numbered folder; `practice/` holds everyday and test runs (not results).
Start with the folder's `README.md`.

| Folder | Question | Status |
| --- | --- | --- |
| [01-baseline-replication](01-baseline-replication/) | Does G2FUZZ beat AFL++(cmplog) on the paper's targets with our setup? | done (phases B + C, 2026-10-26) |
| [02-model-sweep](02-model-sweep/) | How much does the choice of LLM change what G2FUZZ finds on 15 targets? | on hold: 03 runs this design on quantumcore |
| [03-model-sweep-qc](03-model-sweep-qc/) | 02's question and design, run on quantumcore's GPUs and CPUs | campaigns finished 2026-11-01; analysis to do |
| [04-model-sweep-qc-24h](04-model-sweep-qc-24h/) | 03's design with 24 h campaigns (the paper's length), AFL++ output in the campaign folders | campaigns finished 2026-11-07; analysis to do |
| [05-model-sweep-qc-24h-nosched](05-model-sweep-qc-24h-nosched/) | 04's design with the `random` (upstream) generator scheduler, not `ucb`: a scheduler-off baseline for 04 | campaigns finished 2026-11-12; analysis to do |
| [practice](practice/) | Practice and test runs; the `scripts/fuzz` default | always open |

## New study
Copy [TEMPLATE/](TEMPLATE/) to `NN-<name>/` and add a row above. Describe the campaigns in
`launch/study.conf` (targets, arms, reps, secs, seeds; the template's example explains each), then run them with
`scripts/study`:

```bash
scripts/study show  NN-name                          # the campaigns study.conf describes
scripts/study start NN-name --servers --dry          # what start would launch, and which model servers it would start
scripts/study start NN-name --servers --background   # the whole study (below)
scripts/study status NN-name                         # any time: the driver, the servers, one line per campaign
```

`--background` submits a small Slurm job (the driver) that checks every 10 min until every campaign has finished:
it launches campaigns (never one twice), starts each model's server when its campaigns need one and stops it once
they are done (`--servers`), and writes `results/<arm>-r<reps>.csv` for each finished arm and `results/campaigns.csv`
at the end. `scripts/study results NN-name` writes them by hand. Stop the driver with `scancel <job>`; `start` again
picks up where it left off.

- One question per study. Never write into another study's folder; a finished study's campaigns don't change.
- Parts: `README.md`, `launch/` (`study.conf`, or the exact commands), `analysis/`, `results/`, `campaigns/` (data,
  git-ignored). `scripts/study` puts every campaign in the study's `campaigns/` and writes a `launch.txt` into each;
  a hand-written launcher must set `G2F_EVAL=<study>/campaigns` itself. Optional `setup/`: checks that decided how
  to run the study (not results).
- Compare with an earlier study by path, e.g. `01-baseline-replication/campaigns/B-*-g2432-*`.
- Targets, model weights and code stay outside `experiments/`.

## Results columns
`results/*.csv` (`scripts/study`) hold one row per campaign:

| Column | Meaning |
| --- | --- |
| `study` | The study's folder |
| `campaign` | The campaign's folder in `campaigns/`: `<arm>/<target>-r<rep>` |
| `arm` | `afl`: AFL++ alone, from the target's stock seeds (no LLM). Otherwise the model G2FUZZ used |
| `target` | The program fuzzed |
| `rep` | Repetition, from 1 to the study's `reps` |
| `state` | `done`: fuzzed the full time. `done (short)`: under 95% of it (stopped early; a campaign excluded after two failures shows this way). `no seeds`: the model's generators made no seeds, so nothing was fuzzed (a result, not a failure) |
| `edges` | Coverage: edges of the target's code AFL++ reached (`fuzzer_stats` `edges_found`) |
| `crashes` | Crashing inputs AFL++ saved (`saved_crashes`); several can be one bug |
| `execs/s` | Runs of the target per second, averaged over the campaign (`execs_per_sec`). The nodes are shared, so compare within one study |
| `run_s` | Seconds fuzzed (`run_time`); the study's `secs` is a full run (21600 in 03, 86400 in 04) |
| `generators` | Python seed generators the model wrote (0 for `afl`) |
| `llm_steps` | In-run LLM steps: G2FUZZ asks the model to change a generator after coverage stalls for 300 s (`Gen-M start` in `fuzz.log`) |
| `llm_calls` | Requests to the model's server, for seed generation and in-run steps (lines in `llm_calls.jsonl`) |
| `llm_errors` | Of those, the ones that failed, for any reason (blank for `afl`) |
| `llm_400` | Of the failures, the server's HTTP 400 (Bad Request): almost always a prompt longer than the model's context (the study's README gives each model's) |
| `llm_cut` | Answers cut off at the context limit (`finish` = `length`). `-`: not logged (an image from before 2026-10-30) |

When a study finishes, `scripts/results-xlsx NN-name --inputs` writes two files for readers outside Tempest:
- `results/NN-name.xlsx`: these tables as a "column definitions" sheet, then the sheets below. It needs openpyxl
  (`python3 -m pip install --user openpyxl`).
  - **models:** one row per model and target, over the campaigns that fuzzed the full time.
  - **campaigns:** `results/campaigns.csv`.
  - **crashes**, **hangs:** one row per input AFL++ saved as a crash or a hang (read from the campaign folders).
  - **reruns:** one row per failed run moved aside to run again (`campaigns/.retried/MOVED.txt`).
- `results/NN-name-crashes.tar.xz`: the crashing inputs, at the crashes sheet's `file` paths. Git-ignored (03's is
  30 MB): attach it to a GitHub release instead.

The models sheet:

| Column | Meaning |
| --- | --- |
| `done` | Campaigns that fuzzed the full time: the ones the other columns describe |
| `no_seeds` | Campaigns whose generators made no seeds |
| `short` | Campaigns stopped early (`done (short)`: excluded after two failures) |
| `edges_median` | Median `edges` |
| `edges_min` | Lowest `edges` |
| `edges_max` | Highest `edges` |
| `edges_vs_afl` | `edges_median` divided by `afl`'s on the same target (1.05: 5% more edges than AFL++ alone) |
| `crashes_median` | Median `crashes` |
| `execs/s_median` | Median `execs/s` |

The crashes and hangs sheets:

| Column | Meaning |
| --- | --- |
| `crash` | AFL++'s number for the crash in its campaign (`crashes/id:NNNNNN,...`) |
| `hang` | AFL++'s number for the hang in its campaign (`hangs/id:NNNNNN,...`): an input that ran past AFL++'s time limit |
| `signal` | How the target died: `SIGSEGV` (11, a bad memory access), `SIGABRT` (6, an abort, e.g. a failed check), `SIGTRAP` (5), `SIGBUS` (7), `SIGFPE` (8, e.g. a division by zero) |
| `found_s` | Seconds into fuzzing when AFL++ found it |
| `execs` | Runs of the target before it |
| `op` | The AFL++ mutation that made it (`havoc`, `colorization`, `quick`, ...) |
| `src` | The queue entry it was made from (`queue/id:NNNNNN,...`) |
| `bytes` | Its size |
| `sha1` | Of its contents: the same input in several campaigns has the same sha1 |
| `file` | The input itself, under the study's `campaigns/` on Tempest (git-ignored) |

The reruns sheet:

| Column | Meaning |
| --- | --- |
| `moved` | When the failed run was moved aside, so the campaign could run again |
| `first_job` | The failed run's Slurm job |
| `ended` | How the failed run ended, as logged when it was moved |
| `first_run_s` | Seconds the failed run fuzzed |
| `why` | The note written when it was moved: the cause, where it was looked into |
| `bug` | The `docs/KNOWN_BUGS.md` entry the note names (or, for a full node disk, describes: OURS-3), or `seed timeout` (a seed over 1000 ms at start-up; not a bug) |
| `rerun_state` | The campaign's `state` after the rerun (`done (short)`: it failed again and is excluded) |
| `first_run` | The failed run's folder, under the study's `campaigns/` (git-ignored) |
