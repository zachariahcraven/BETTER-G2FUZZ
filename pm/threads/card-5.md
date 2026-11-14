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
