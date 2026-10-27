# Experiments

One folder per study, numbered in the order they started. Read a study's `README.md` first.

| Study | Question | Status | In the report |
| --- | --- | --- | --- |
| [01-baseline-replication](01-baseline-replication/) | Does G2FUZZ beat AFL++(cmplog) on the paper's targets with our setup (local LLM; AFL++ 4.32c and 5.03c)? | phase B done + analyzed (2026-10-25); phase C needs approval | yes (its `setup/` no) |

## Starting a study
Copy [TEMPLATE/](TEMPLATE/) to `NN-<short-name>/` and add a row above. Rules:

- **One question per study.** A study never writes into another study's folder.
- **Same parts everywhere:** `README.md`, `launch/` (the exact commands), `analysis/`, `results/` (report tables and
  figures), `campaigns/` (the data). Add `setup/` only for checks that decided *how* to run the study; they aren't results.
- **Campaign data stays out of git:** `campaigns/` folders are git-ignored. Launchers put campaigns there with
  `export G2F_EVAL=<study>/campaigns` before `scripts/fuzz new/run`; `scripts/fuzz status/results/watch` need the same.
- **Compare with an earlier study by reference,** e.g. "baseline = `01-baseline-replication/campaigns/B-*-g2432-*`",
  with the same targets, model and image versions. A finished study's campaigns don't change.
- Shared pieces stay outside `experiments/`: the targets (`g2f-targets/`), model weights (`shared-models/`) and the
  code (`scripts/`, `targets/`, `tests/`).

Everyday or practice runs belong in `eval/` (the `scripts/fuzz` default), not here.
