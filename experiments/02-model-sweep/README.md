# 02 Model sweep

**Question:** how much does the choice of LLM change what G2FUZZ finds, across 15 of the paper's targets?
**Owner:** n59m742 (+ team). **Status:** planned. **Started:** 2026-10-29.

## Design
- **Arms:** one per model, G2FUZZ only (`scripts/fuzz run`, no `--afl`). One model at a time: all 15 targets, then
  the next model.
- **Targets:** the 15 in [launch/targets.txt](launch/targets.txt) (paper versions, `g2f-targets/paper`), with
  the reason for each and what was left out.
- **Models:** folders in `students/shared-models`, served by `scripts/fuzz llm start --model <folder>`.
- **Run:** 6 h of fuzzing per campaign (default), rep 1 first, image `g2fuzz.sif` as recorded in each campaign's
  `launch.txt`, generator scheduler **`ucb`** for every campaign (the team's UCB bandit; set in `launch/sweep`,
  recorded in each `launch.txt`).
- **Compared against:** the Qwen3.8 runs of the same image are the reference. For the 7 UNIFUZZ targets,
  `01-baseline-replication/campaigns/B-<target>-g2432-r*` is an earlier Qwen3.8 baseline (older image bdb816a, and the
  random scheduler: a difference in two things, not one).

## Running one model
On Tempest, from the repo root:

```bash
scripts/fuzz llm start 48 --model phi-4             # the model's server (1 A40); wait for "ready":
scripts/fuzz llm status --model phi-4
experiments/02-model-sweep/launch/sweep start phi-4 --wait     # in tmux: launches all 15 over a few hours
experiments/02-model-sweep/launch/sweep status phi-4           # any time: one line per target
experiments/02-model-sweep/launch/sweep csv phi-4 > experiments/02-model-sweep/results/phi-4-r1.csv   # when all are done
scripts/fuzz llm stop --model phi-4                 # once every campaign has finished
```

- `start` never launches a campaign twice, so it is safe to rerun (without `--wait` it launches what it can and
  says what is left). `DRY=1` prints what it would do.
- A `failed` campaign (ended without fuzzer_stats) is not retried by itself: read its `slurm-*.out` and
  `seedgen.log`, move the folder to `campaigns/<model>/failed/`, and run `start` again.
- At most `MAX_SEEDGEN` (default 4) campaigns of a model generate seeds at once. Seed generation takes 20 min to
  2 h per target on an A40 (Qwen3.8 test, 2026-10-29: jhead 22 min, gdk-pixbuf-pixdata 115 min; multi-format
  targets, pdftotext and mp42aac take longest), so all 15 are launched after several hours, and the model is done
  about 6 h after the last one starts. Start the server for that long (48 h is safe). `sweep` gives each job 5 h for
  seed generation (`G2F_SEEDGEN_MIN=300`); a run that still got cut short shows as `done (short)` in `status`.
- Campaigns: `campaigns/<model>/<target>-r<rep>/` (git-ignored). `scripts/fuzz status|results|watch` work on them with
  `G2F_EVAL=experiments/02-model-sweep/campaigns/<model> G2F_TARGET=<target>`.

## Layout
| Folder | Holds |
| --- | --- |
| `launch/` | `sweep` (launches and summarizes a model's campaigns) and `targets.txt` |
| `results/` | One CSV per model and rep (`sweep csv`), then tables and figures for the report |
| `campaigns/` | Campaign data (git-ignored): `<model>/<target>-r<rep>/` |
| `setup/sweep-test/` | The launcher's end-to-end test (2 targets, 600 s); not results |

## Results
Filled in when the study ends. `edges` in `sweep status/csv` come from AFL++'s own `fuzzer_stats`: fine for comparing
models on the same target (same binary). For the report, replay the queues as in `01-baseline-replication/analysis`.
