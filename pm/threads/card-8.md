# card-8: Submit future Slurm jobs with --no-requeue (requeue caused duplicate campaigns)

## Note nom-nom 2026-11-13 17:15
During the 2026-11-13 outage Slurm requeued 28 jobs whose processes were still running, then started a few copies beside the live originals (10:59-11:03) in the same campaign folders. Idea: `--no-requeue` on every sbatch in `scripts/fuzz` / `scripts/study`, or `SBATCH_NO_REQUEUE=1`.

## Note nom-nom 2026-11-13 17:46
Files: scripts/fuzz, scripts/study, scripts/tests/test_fuzz_cli.sh, build/targets/build-paper.sh

## Note nom-nom 2026-11-13 17:46
`--no-requeue` added to all four sbatch calls: campaign jobs and LLM servers (`scripts/fuzz`), the study driver (`scripts/study`), target builds (`build/targets/build-paper.sh`). A campaign lost to a node failure now ends instead of restarting; it reads "done (short)" and `scripts/study start --retry-failed` reruns it.

**Tested:** `scripts/tests/test_fuzz_cli.sh` against HEAD's `scripts/fuzz`, on the Tempest login node in a private scratch copy (`~/.cache/nomnom-clitest`, fake Slurm, nothing submitted). The only differences from HEAD are the added flag on sbatch lines; all contracts ok, including the new "no job is requeued after a node failure". The test still exits 1 because it reports any difference from HEAD; it will pass once this is committed. It cannot run on the Mac (needs GNU `touch`).

**Not covered:** the pending A02/A00 relaunch (card-2) runs from the 01db4f3 checkout, so it does not get this. Exporting `SBATCH_NO_REQUEUE=1` when starting those drivers is the stopgap; that is the relaunch session's call. The `watch-alfred` job is submitted by hand, outside the repo: add `--no-requeue` to that command too.

`build-paper.sh`'s change was only syntax-checked (`bash -n`). `scripts/fuzz` and `scripts/tests/test_fuzz_cli.sh` are shared with card-9 (one line each for `G2F_FONT_HINT`).

## Note nom-nom 2026-11-13 17:46
Review:
##### To check
- `git diff scripts/fuzz scripts/study build/targets/build-paper.sh`: each of the 4 sbatch lines gained `--no-requeue` and nothing else changed (plus one `G2F_FONT_HINT` line in `scripts/fuzz` from card-9).
- On Tempest after pulling: `scripts/tests/test_fuzz_cli.sh` prints `ok    no job is requeued after a node failure`.
##### Changed
Every sbatch call now passes `--no-requeue` (campaigns, LLM server, study driver, target builds), so a node failure can no longer start a second copy of a job beside a live one. A lost campaign ends and is rerun with `--retry-failed`. One new test check.

## Note human 2026-11-13 17:57
Approved and committed (9a2c515).
