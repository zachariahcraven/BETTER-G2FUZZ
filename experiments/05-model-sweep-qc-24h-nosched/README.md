# 05 Model sweep on quantumcore, 24 h, no scheduler

**Question:** what does this repo's `ucb` generator scheduler contribute? [04](../04-model-sweep-qc-24h/README.md)'s
study run again with one change: the `random` generator scheduler (upstream G2FUZZ's pick) in place of `ucb`. Because
the models, target builds, image, hardware, reps and time are all 04's, 05 vs 04 is a direct per-cell comparison of
code coverage and unique bugs, and 05 is a scheduler-off baseline for 04 that needs no comparison to the paper.
**Owner:** n59m742. **Status:** not launched. **Started:** 2026-11-07.

## Design
- **One difference from 04:** `scheduler = random` (`launch/study.conf`), i.e. `G2F_GENERATOR_SCHEDULER=random`.
  When an LLM step mutates a generator after a coverage stall, G2FUZZ picks the parent generator at random (upstream's
  behaviour) instead of by this repo's UCB bandit (`g2fuzz/py_utils/generator_scheduler.py`). Nothing else changes:
  same eight models plus the `afl` baseline, same 15 targets (`launch/targets.txt`), 5 reps, 24 h, same image, same
  `g2f-targets` builds, same servers and accounts, `output = campaign`. 675 campaigns.
- **No code change, no new image:** the `random` path is already in the image 03 and 04 used; only the config differs.
- For the arms, the `output = campaign` rationale, the dropped starcoder2, and the pinned settings (vLLM, weights'
  revisions, temperatures, contexts, chat templates), see [04's README](../04-model-sweep-qc-24h/README.md#design) —
  all of it holds here unchanged.

## Analysis plan (fixed before launch)
- **The headline comparison:** 05 vs 04, per target, for `edges` (coverage, replayed on one common binary as in
  `01-baseline-replication/analysis`) and for unique bugs (crash triage, deduplicated by the top three ASan frames).
  Mann–Whitney U and Vargha–Delaney A12 on the 5 reps per cell; a near-tie is a valid, reportable result.
- **Everything else is 04's plan:** per-target medians, Friedman + Nemenyi over the 15 targets, each model against
  `afl`, the t=0 `initial_seeds` coverage to separate seed generation from fuzzing, and the `no seeds` handling. The
  sensitivity analysis also repeats on the targets where every model made seeds.
- **Failures:** a `failed` or `done (short)` campaign is run again once (`--retry-failed`; its first run stays in
  `campaigns/.retried/`); a campaign that fails twice is excluded and listed. The upstream G2FUZZ crashes
  ([G2F-1](../../docs/KNOWN_BUGS.md#g2f-1-in-run-seeds-skip-afls-size-checks),
  [G2F-3](../../docs/KNOWN_BUGS.md#g2f-3-afl-fuzz-heap-corruption-in-g2fuzz-runs)) and the libpcap memory kills
  ([OURS-4](../../docs/KNOWN_BUGS.md#ours-4-the-kernels-file-name-cache-counts-against-a-campaigns-memory)) recur, with
  04's rerun rules.

## Running it
On Tempest, from the repo root (members of `priority-quantumcore` only, with that group's OK):

```bash
scripts/study start 05-model-sweep-qc-24h-nosched --servers --dry          # check; changes nothing
scripts/study start 05-model-sweep-qc-24h-nosched --servers --background   # run it all
scripts/study status 05-model-sweep-qc-24h-nosched                         # progress, other users, failures
```
- Run, as 04 was, with n59m742's private driver (`~/g2f-04-driver/study`: `scripts/study` plus the class-account
  overflow), since partners have no quantumcore:
  `STUDY_DRIVER_DAYS=14 STUDY_EXTRA_ACCOUNT=priority-csci-591-automated-vulnerability-discovery STUDY_EXTRA_MAX=120
  ~/g2f-04-driver/study start 05-model-sweep-qc-24h-nosched --servers --background`.
- **Results:** the driver writes `results/<model>-r1-5.csv` as each model finishes
  ([columns](../README.md#results-columns)); `scripts/results-xlsx 05-model-sweep-qc-24h-nosched --inputs` builds the
  workbook and packs the crashing inputs.

## Known limitations (recorded, not changed)
- **Expect a small coverage delta.** The scheduler only chooses which generator the in-run LLM step mutates, and 04's
  own data shows those steps add little coverage (about 0% new edges beyond the first few, close to plain AFL++'s own
  stall-escape rate). So 05's coverage may land close to 04's. That is the point of the baseline, not a failure of it:
  a near-tie shows the UCB scheduler doesn't materially change coverage at 24 h, which makes 04 comparable to an
  upstream-selection baseline. Unique bugs may differ more than coverage, since random selection explores a different
  set of generators.
- **All of 04's limitations apply** (it mostly measures seed generation; context, sampling and reasoning per model;
  shared-node execs/s; MAGMA canaries off; the G2F-1/G2F-3 crashes). See
  [04's README](../04-model-sweep-qc-24h/README.md#known-limitations-recorded-not-changed).

## Results
Filled in when the study ends.
