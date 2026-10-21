# Review record: a0-runners

- Files: experiments/runners/run-lineup.sbatch, experiments/runners/run-bandit.sbatch
- Spec: tasks/a0/runners.md
- Author: legacy
- Status (computed from the passes below): PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes)

## Events (in order)

- Pass 1: gemma, checklist 7-parity -> **clean** (2026-10-15 17:53:48)
- Pass 2: qwen38, checklist 1-spec -> **findings** (2026-10-15 17:58:48)
  - F1 [low] experiments/runners/run-bandit.sbatch:26: The default value of SCHEDS is 'random bandit' in the code but the spec states the default is 'bandit random' (reversed order).
- Judgement (pass 2, F1): **reject**: Order of the SCHEDS default is irrelevant: both arms run; spec wording only.
- Pass 3: gemma, checklist 5-errors -> **findings** (2026-10-15 18:13:21)
  - F1 [high] experiments/runners/run-lineup.sbatch:94: Failure of the fuzzing run is silenced and treated as a success because the exit code is discarded in a pipeline to grep.
  - F2 [high] experiments/runners/run-bandit.sbatch:49: Failure of the fuzzing run is silenced and treated as a success because the exit code is discarded in a pipeline to grep.
  - F3 [medium] experiments/runners/run-lineup.sbatch:94: The script does not exit with a failure status if campaigns fail, allowing it to produce a log that looks complete.
- Judgement (pass 3, F1): **valid**: Confirmed by reading: scripts/fuzz new/run exit status lost in the grep pipeline; a campaign that fails to start leaves no trace in the runner log.
- Judgement (pass 3, F2): **valid**: Confirmed by reading: scripts/fuzz new/run exit status lost in the grep pipeline; a campaign that fails to start leaves no trace in the runner log.
- Judgement (pass 3, F3): **valid**: Confirmed by reading: scripts/fuzz new/run exit status lost in the grep pipeline; a campaign that fails to start leaves no trace in the runner log.
- Fix round 1: Claude (shell glue): start_campaign helper in both runners logs 'FAILED to start (exit N)' with the last output lines; smoke-tested with a fake scripts/fuzz (ok, new fails, run fails).
- Pass 4: qwen38, checklist 7-parity -> **clean** (2026-10-15 18:15:49)
- Pass 5: gemma, checklist 1-spec -> **findings** (2026-10-15 18:17:15)
  - F1 [medium] experiments/runners/run-lineup.sbatch:102: The script ignores the G2F_TIMEOUT_MS environment variable required by the spec.
- Judgement (pass 5, F1): **reject**: G2F_TIMEOUT_MS is inherited from the submitting environment (recipes pass it on sbatch --export=ALL) and read by scripts/fuzz at run time; verified -t 100 in run.sh of wad-codernext-r1, wad-baseline-r3, wad-qwen4b-r5. The reproducer only grepped the runner text.
- Pass 6: qwen38, checklist 3-data-io -> **findings** (2026-10-15 18:22:29)
  - F1 [low] experiments/runners/run-lineup.sbatch:88: The sed regex `\([0-9]\)` matches only a single digit, so an sbatch line like `#SBATCH --gres=gpu:a40:12` is not matched; `g` is silently empty and the server is submitted without the `G2F_VLLM_GRES` override, allocating the wrong number of H100s with no log warning.
- Judgement (pass 6, F1): **reject**: Serve files request a40:1 or a40:2; no node has more than 4 GPUs, so a multi-digit count cannot occur. Not a defect in practice.
