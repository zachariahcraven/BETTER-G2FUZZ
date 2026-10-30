# 02 Model sweep

**Question:** how much does the choice of LLM change what G2FUZZ finds, across 15 of the paper's targets?
**Owner:** n59m742 (+ team). **Status:** on hold (not started): [03-model-sweep-qc](../03-model-sweep-qc/) runs this
design on quantumcore. **Planned:** 2026-10-29.

## Design
- **Arms:** one per model in `students/shared-models`, G2FUZZ only, generator scheduler **`ucb`**
  ([launch/study.conf](launch/study.conf)).
- **Targets:** the 15 in [launch/targets.txt](launch/targets.txt) (paper versions, `g2f-targets/paper`), with the
  reason for each and what was left out.
- **Run:** 6 h of fuzzing per campaign, rep 1; image, server and settings recorded in each campaign's `launch.txt`.
- **Compared against:** the Qwen3.8 runs of the same image are the reference. For the 7 UNIFUZZ targets,
  `01-baseline-replication/campaigns/B-<target>-g2432-r*` is an earlier Qwen3.8 baseline (older image bdb816a, and the
  random scheduler: a difference in two things, not one).

## Running it
On Tempest, from the repo root:

```bash
scripts/study start 02-model-sweep --servers --dry          # what it would start and launch
scripts/study start 02-model-sweep --servers --background   # the whole study, in one command
scripts/study status 02-model-sweep                         # any time: the driver, the servers, one line per campaign
```

- The driver (a small Slurm job, log `campaigns/study-driver-<job>.log`) starts each model's server on a class A40
  when its campaigns need it, launches them (at most 4 seed generations per model), stops the server when the model
  is done and writes `results/<model>-r1.csv`. `scancel <job>` stops it; `start` again picks up where it left off.
  One model only: add `--only arm=<model>`.
- **Time:** about 12–14 h per model (seed generation 20 min to 2 h per target, then 6 h of fuzzing). The class has 2
  A40s, so two models run at once: **about 36–42 h for the whole study**, and teammates' servers on the class account
  queue behind it. On quantumcore's H100s instead (members only, with that group's OK): see 03, about 20–28 h.
- A `failed` campaign (no fuzzer_stats) isn't retried by itself: read its `slurm-*.out` and `seedgen.log` and move it
  to `campaigns/<model>/failed/`; the driver then launches it again. `done (short)` in `status`: Slurm's limit cut it.
- `scripts/fuzz status|results|watch` work on a campaign with
  `G2F_EVAL=experiments/02-model-sweep/campaigns/<model> G2F_TARGET=<target>`.

## Layout
| Folder | Holds |
| --- | --- |
| `launch/` | `study.conf` (the campaigns) and `targets.txt` (the 15 targets, with reasons) |
| `results/` | `<model>-r1.csv` per finished model and `campaigns.csv` (written by `scripts/study`), then the report's tables and figures |
| `campaigns/` | Campaign data (git-ignored): `<model>/<target>-r<rep>/` |
| `setup/sweep-test/` | Data of the first end-to-end test (2026-10-29, Qwen3.8, 600 s; seed generation took 22 min on jhead and 115 min on gdk-pixbuf-pixdata); not results |

## Results
Filled in when the study ends. `edges` in `scripts/study status/csv` come from AFL++'s own `fuzzer_stats`: fine for
comparing models on the same target (same binary). For the report, replay the queues as in
`01-baseline-replication/analysis`.
