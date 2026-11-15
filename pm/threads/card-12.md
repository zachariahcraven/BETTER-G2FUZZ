# card-12: OURS-7: LLM worker dies on a gen_seeds file it cannot delete (3 A00 continuous campaigns)

## Note nom-nom 2026-11-13 17:57
Files: g2fuzz/llm_worker.py, g2fuzz/tests/test_llm_worker.py, docs/KNOWN_BUGS.md

## Note nom-nom 2026-11-13 17:57
Found while running `scripts/compare` on A00 for card-3 ("worker traceback" in 3 continuous campaigns).

In continuous `mp42aac-r3`, `-r4`, `-r5` the worker ended with `OSError: [Errno 16] Device or resource busy: '/eval/mp42aac_output/default/gen_seeds/.nfs...'` from `os.remove()` in `publish()`. Their last LLM steps started 13,971 s, 12,926 s and 8,470 s into the 21,600 s run (76, 70 and 72 steps; r1 and r2 ran 189 and 131 steps to the end). afl-fuzz kept running, so the campaigns read `done` at full length but had no LLM for the last 35% to 61% of the run. No other A00 campaign has a traceback.

**Fix:** `publish()` skips `.nfs*` names; an `OSError` on any one file is logged and counted as `skipped`, and the worker goes on. Entry OURS-7 added to `docs/KNOWN_BUGS.md`.

**Tested:** `python3 g2fuzz/tests/test_llm_worker.py` on the Mac: 10 tests OK, including the new `test_publish_survives_files_it_cannot_remove` (a `.nfs*` file plus a faked EBUSY on remove). Not tested on NFS.

**For the relaunch (card-2):** the reruns use the 01db4f3 image, which does not have this fix, so continuous campaigns can hit it again. These three mp42aac campaigns are not in the current rerun set; rerunning them is a decision for the user and the relaunch session (`--retry-failed` will not pick them up, they read `done`).

**Not known:** why a generator's file is still open when the step ends.

## Note nom-nom 2026-11-13 18:00
Review:
##### To check
- `python3 g2fuzz/tests/test_llm_worker.py`: 10 tests OK (about 25 s).
- `git diff g2fuzz/llm_worker.py`: `publish()` now calls `publish_one()` per file inside a try/except; the per-file logic is the same.
- Decide whether continuous mp42aac-r3/r4/r5 get rerun (see this card's notes).
##### Changed
The LLM worker no longer ends when it cannot delete a file in `gen_seeds/` (an NFS `.nfs*` leftover): it skips those names and logs any other per-file error. This ended the worker partway through 3 of A00's continuous mp42aac campaigns. New test; OURS-7 added to KNOWN_BUGS. Not tested on NFS.

## Note human 2026-11-13 18:02
Approved and committed (8b6fa1b).
