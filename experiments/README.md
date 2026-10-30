# Experiments

Every campaign lives here. A study is one numbered folder; `practice/` holds everyday and test runs (not results).
Start with the folder's `README.md`.

| Folder | Question | Status |
| --- | --- | --- |
| [01-baseline-replication](01-baseline-replication/) | Does G2FUZZ beat AFL++(cmplog) on the paper's targets with our setup? | done (phases B + C, 2026-10-26) |
| [02-model-sweep](02-model-sweep/) | How much does the choice of LLM change what G2FUZZ finds on 15 targets? | planned (2026-10-29) |
| [practice](practice/) | Practice and test runs; the `scripts/fuzz` default | always open |

## New study
Copy [TEMPLATE/](TEMPLATE/) to `NN-<name>/` and add a row above.
- One question per study. Never write into another study's folder; a finished study's campaigns don't change.
- Parts: `README.md`, `launch/` (the exact commands), `analysis/`, `results/`, `campaigns/` (data, git-ignored).
  Launchers set `G2F_EVAL=<study>/campaigns` for every `scripts/fuzz` call. Optional `setup/`: checks that decided
  how to run the study (not results).
- Compare with an earlier study by path, e.g. `01-baseline-replication/campaigns/B-*-g2432-*`.
- Targets, model weights and code stay outside `experiments/`.
