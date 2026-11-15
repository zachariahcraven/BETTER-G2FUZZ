# card-10: OURS-5: retry open() on ERESTARTSYS in afl-fuzz

## Note nom-nom 2026-11-13 17:15
From `docs/KNOWN_BUGS.md` (OURS-3 and OURS-4 are also open there). Offered as agent work by session alfred-tweak-rounds-study; not started, the user has not answered the offer.

## Note nom-nom 2026-11-13 17:46
Files: afl/src/afl-fuzz-queue.c, afl/src/afl-fuzz-bitmap.c, afl/include/afl-fuzz.h, docs/KNOWN_BUGS.md

## Note nom-nom 2026-11-13 17:46
Written by a sub-agent, diff reviewed by nom-nom.

New `queue_testcase_open()` in `afl/src/afl-fuzz-queue.c`: opens a queue entry read-only; on `EINTR` or errno 512 it retries, 5 attempts in all with 50/100/200/400 ms between (about 0.75 s at most). Any other errno fails at once, so the existing `PFATAL` fires as before. Used by `load_testcase()` (behind `queue_testcase_get()` and `queue_testcase_retake()`) and by the re-read of a new entry in `save_if_interesting()` (`afl-fuzz-bitmap.c`).

Left alone on purpose: `perform_dry_run()`'s start-up read (`afl-fuzz-init.c`), `sync_fuzzers()` and `check_if_text()` (both already fail soft).

**Tested:** all afl-fuzz sources compiled on the Mac with the Makefile's warning flags (no LTO, no Python support): 0 warnings, binary prints its help. A standalone test with a faked `open()` passes 8 cases (success, ENOENT/EACCES immediate, EINTR/512 once, 512 four times, 512 and EINTR forever).

**Not tested:** on NFS, on Linux, or in the image build.

**Doubts:** a failing `read()` after the open is not retried; the 0.75 s window is a guess (one occurrence in about 1,400 runs gives no data on how long the condition lasts).

## Note nom-nom 2026-11-13 17:46
Review:
##### To check
- `git diff afl/`: one new helper `queue_testcase_open()` and two call sites switched to it.
- `git diff docs/KNOWN_BUGS.md`: the OURS-5 row and entry say fixed in code, not deployed, not tested on NFS.
- It ships with the next image build (card-5); the real check is that afl-fuzz builds there.
##### Changed
afl-fuzz retries a failed read-open of a queue entry on EINTR / errno 512 (5 tries, about 0.75 s) before stopping as it did. Other errors behave as before. KNOWN_BUGS OURS-5 is now "fixed in code, not deployed". Compiled and logic-tested on the Mac only; not tested on NFS or in the image.

## Note human 2026-11-13 17:55
Approved and committed (502fd5d).
