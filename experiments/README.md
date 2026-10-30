# Experiments

Every campaign lives here. A study is one numbered folder; `practice/` holds everyday and test runs (not results).
Start with the folder's `README.md`.

| Folder | Question | Status |
| --- | --- | --- |
| [01-baseline-replication](01-baseline-replication/) | Does G2FUZZ beat AFL++(cmplog) on the paper's targets with our setup? | done (phases B + C, 2026-10-26) |
| [02-model-sweep](02-model-sweep/) | How much does the choice of LLM change what G2FUZZ finds on 15 targets? | on hold: 03 runs this design on quantumcore |
| [03-model-sweep-qc](03-model-sweep-qc/) | 02's question and design, run on quantumcore's GPUs and CPUs | planned (2026-10-30) |
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
