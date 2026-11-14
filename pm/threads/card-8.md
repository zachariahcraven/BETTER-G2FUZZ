# card-8: Submit future Slurm jobs with --no-requeue (requeue caused duplicate campaigns)

## Note nom-nom 2026-11-13 17:15
During the 2026-11-13 outage Slurm requeued 28 jobs whose processes were still running, then started a few copies beside the live originals (10:59-11:03) in the same campaign folders. Idea: `--no-requeue` on every sbatch in `scripts/fuzz` / `scripts/study`, or `SBATCH_NO_REQUEUE=1`.
