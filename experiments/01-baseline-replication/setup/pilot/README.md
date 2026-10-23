# Pilot (2026-10-23)

**Question:** do all 4 arms run end to end on the paper's targets, in both repos?
**Answer:** yes, after 3 fixes. 15 min (900 s) of fuzzing per campaign on jhead (an image target),
libpng (`libpng_libpng_read_fuzzer`, FuzzBench) and mp42aac (UNIFUZZ, extra arguments).

- **AFL arms** (`--afl`): started by hand with `scripts/fuzz run pilotA-afl<432|503>-<target> 900 --afl`, with
  `G2F_TARGETS` = that repo's paper tree.
- **G2FUZZ arms** (`--test`: the LLM mutation step fires after 10 s without new coverage): [launch-g2.sh](launch-g2.sh),
  model Qwen3.8-27B-FP8-nothink.

| Campaign | Edges (own binary) | Crashes | Notes |
| --- | --- | --- | --- |
| afl432 / afl503 jhead | 452 / 380 | 89 / 3 | |
| afl432 / afl503 libpng | 1524 / 1455 | 0 / 0 | |
| afl432 / afl503 mp42aac | 993 / 997 | 65 / 81 | slow start only (1.5–1.8M execs in 900 s) |
| g2432 / g2503 jhead | 527 / 434 | 14 / 20 | LLM step imported 44 / 26 seeds mid-run |
| g2432 libpng | 1401 | 0 | **out of memory** at 4 GB after 188 s; rerun `-b` with 8 GB: 1499, full 900 s |
| g2503 libpng | 1457 | 0 | on the A40 server: calls ~2.5x slower than the A100 |
| g2432 mp42aac | 1116 | 46 | 1331 s of run time for 900 s of fuzzing: `--test` LLM steps add time |
| g2503 mp42aac | — | | **failed**: a generator wrote a folder of frames; rerun `-b` after the fix: 1279, 56 crashes |

Edges are each arm's own binary and not comparable between AFL++ versions (the study replays them on one binary).

**Fixes this found** (all in both repos, 2026-10-23):
1. 8 GB per campaign instead of 4 GB (LLM-written PNG seeds of ~10 MB).
2. `scripts/fuzz`: only the files in `gen_seeds/` become seeds (a folder stopped `cp`, so afl-fuzz never ran). The
   exp workspace had this fix since October; it hadn't been ported.
3. G2FUZZ-upgradedAFL had no `g2fuzz.sif.version`, so its campaigns recorded no image version: written, and its
   campaigns' `image-version.txt` filled in (marked as filled in later).

Also decided here: phase B uses only the A100 server, so LLM speed is the same for every campaign.
Campaigns: `campaigns/pilotA-<arm>-<target>[-b]/` (git-ignored).
