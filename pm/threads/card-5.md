# card-5: Deploy window after A02: new image, builders, rebuild all 25 targets (ALF-1 guard + CmpLog fix)

## Note nom-nom 2026-11-13 17:15
Only after A02 ends. Waits on card-2 and card-4.

1. Pull on Tempest.
2. `scripts/tempest-image` (its ssh upload can drop: use `rsync --partial`, then run its convert step by hand).
3. `scripts/tempest-builders`.
4. Rebuild all 25 projects with `build/targets/build-paper.sh` into a staging `G2F_TARGETS_ROOT`.
5. Rename `g2f-targets-alfred/paper` to `paper-01db4f3` (A00/A02 replays need it), then move the staged tree in.
6. Check: `nm <t>.afl | grep __alf_guard_reserve`, and CmpLog hooks present in `gdk-pixbuf-pixdata.cmp` and `mp42aac.cmp`.

What this deploys (both committed in f8ddcbb, not yet in the image):
- **ALF-1**: a real gdk-pixbuf heap overflow (io-bmp.c DoCompressed) writes into AFL's coverage map. AFL++ 5.03c stops the campaign; 4.32c silently counted 100% coverage in 9 runs of studies 04/05. Fix: guard pages around the maps in afl-compiler-rt (`AFL_NO_MAP_GUARD=1` disables).
- **CmpLog**: gdk-pixbuf-pixdata and mp42aac were built with 0 CmpLog hooks in every study so far (build.sh passed `AFL_LLVM_CMPLOG` only to configure).

## Note nom-nom 2026-11-14 19:37
**2026-11-14 19:45 MST: A02 has ended, the deploy can start, but it is blocked on a push.**

- `scripts/tempest-image` refuses unless HEAD is pushed, and Tempest gets `scripts/` by `git pull`. The Mac clone is 6 commits ahead of `origin/alfred` (cards 3, 8, 9, 10, 11, 12), plus card-2's Rounds log row once approved.
- My `git push origin alfred` was denied by the permission classifier, so the push is the human's step.
- Ready otherwise: Docker is running on the Mac; no `alfred-*` jobs on Tempest; 8.9 TB free on the group share.
- DNS on compute nodes is still broken (epyc node checked 19:35: only `nameserver 10.226.104.21`), so every deploy step that runs on a node gets `LOCALDOMAIN=rci.montana.edu`.
- Also noted: `tempest-image` refuses a tree with modified tracked files, and `pm/` files change with every card. I will build from a clean `git worktree` of the pushed HEAD.

## Note nom-nom 2026-11-14 19:37
Blocked: Approve card-2 (commits the A02 row), then push branch alfred to GitHub so the deploy can build from it.
Command: git push origin alfred

## Note human 2026-11-14 19:57
Unblocked: done.

## Note nom-nom 2026-11-14 20:07
Brief: now: push done, Tempest pulled to 455d690; image build running on the Mac
next: install image, builders, rebuild 25 targets, swap paper tree
you: nothing

## Note nom-nom 2026-11-14 20:47
**Deploy progress, 2026-11-14 20:50 MST.**

1. Pull on Tempest: done (now `abe2246`, with the `uncovered` mutator and A01's 7 arms).
2. Image `455d690`: installed 20:08. `tempest-image`'s last step printed "mv: cannot stat build/g2fuzz.sif.new" and still wrote the version file, so `g2fuzz.sif` was the old image under the new version name; I renamed the new file in by hand (kept as `g2fuzz-455d690.sif`; the old one stays as `g2fuzz-01db4f3.sif`). Likely an NFS delay between the compute node and the login node; worth a retry loop in the script.
3. Builders: all six installed 20:18-20:46 (from the `455d690` image).
4. Target rebuilds: 25 jobs submitted, 1291033-1291057, into the staging root `g2f-targets-alfred/staging-455d690/paper` (builders symlinked in; `run-libs.txt` made from the new image).
5. Image again, from `abe2246` (only `g2fuzz/` Python differs, so builders and targets stay valid): building now with `--force` (the build jobs count as `alfred-*` jobs).

Still to do: check each build's test log, `nm <t>.afl | grep __alf_guard_reserve`, CmpLog hooks in gdk-pixbuf-pixdata.cmp and mp42aac.cmp; rename `paper` to `paper-01db4f3`, move the staged tree in, copy the 15 `*.uncovered.json` across.

## Note nom-nom 2026-11-14 21:03
**Deploy done, 2026-11-14 21:00 MST.**

- Image: `build/g2fuzz.sif` is `abe2246 built 2026-11-14 20:47` (carries `py_utils/uncovered.py`); copies `g2fuzz-abe2246.sif`, `g2fuzz-455d690.sif`, `g2fuzz-01db4f3.sif`. Both installs hit the same `mv: cannot stat g2fuzz.sif.new` at the end of `tempest-image`; finished by hand both times.
- Builders: six, from the `455d690` image (AFL++ and LLVM identical to `abe2246`: only `g2fuzz/` Python differs).
- Targets: 25 projects rebuilt in 5-9 min each (jobs 1291033-1291057, all COMPLETED, every test log "0 failure(s)"), 28 `.afl`. Old tree is `g2f-targets-alfred/paper-01db4f3`; new tree is `paper`; file lists identical.
- Checks: `__alf_guard_reserve` in 28 of 28 `.afl` (old jhead.afl: none). CmpLog hook calls: gdk-pixbuf-pixdata.cmp 2,423 (old 0), mp42aac.cmp 4,683 (old 0), jhead.cmp 938 (unchanged).
- The 15 `*.uncovered.json` copied into the new `paper`.
- Left in place: `staging-455d690/` (logs, stage), `uncovered/` (coverage builds and sources).
