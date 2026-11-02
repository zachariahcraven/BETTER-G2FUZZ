# Known bugs

Bugs found in the code our studies run: upstream G2FUZZ and its AFL++ 4.32c, then our own. Each entry says where the
bug is, how it was found, what it does to results, and whether it's fixed. New ones go at the end of their section.

| ID | Where | What | Status |
|---|---|---|---|
| [G2F-1](#g2f-1-in-run-seeds-skip-afls-size-checks) | `afl/src/afl-fuzz.c` `run_gen_seeds()` | in-run generator seeds skip AFL++'s size checks; afl-fuzz segfaults on ones over 1 MiB | **open** (03 and 04 run with it) |
| [G2F-2](#g2f-2-pip_debug-runs-any-answer-as-a-pip-command) | `g2fuzz/py_utils/func.py` `pip_debug_loop()` | any LLM answer is run as a pip command | fixed 2026-10-30 (255c12b) |
| [G2F-3](#g2f-3-afl-fuzz-heap-corruption-in-g2fuzz-runs) | afl-fuzz, G2FUZZ arms only (not located) | heap corruption: glibc stops afl-fuzz mid-run or as it exits | **open** (cause not found) |
| [AFL-1](#afl-1-afl-fuzz-432c-fuzzes-the-cmplog-binary) | `afl/src/afl-fuzz.c` (AFL++ 4.32c) | fuzzes with the CmpLog binary, not the target | open (fixed upstream in 5.03c) |
| [AFL-2](#afl-2-afl-showmap-432c-aborts-on-maps-over-64k) | `afl-showmap` (AFL++ 4.32c) | aborts on coverage maps over 64K | worked around |
| [OURS-1](#ours-1-ucb-snapshot-held-one-formats-generators) | `g2fuzz/py_utils/generator_scheduler.py` | UCB snapshot held only one format's generators | fixed 2026-10-30 (255c12b) |
| [OURS-2](#ours-2-scancel-skipped-the-study-drivers-cleanup) | `scripts/study` `start --background` | `scancel` of the driver left its LLM servers running | fixed 2026-10-30 (uncommitted) |
| [OURS-3](#ours-3-output-on-the-nodes-shared-disk) | `scripts/fuzz run` (each campaign's `job.sbatch`) | AFL++ output is on the node's shared `/tmp`; when it fills, every campaign there stops | **open** (03 and 04 run with it) |

## Upstream G2FUZZ

### G2F-1: in-run seeds skip AFL++'s size checks
- **Where:** `run_gen_seeds()`, `afl/src/afl-fuzz.c:546` (upstream's code, unchanged since 1f3fb99). During fuzzing,
  each LLM mutation step runs G2FUZZ's generators and adds every file they write to the queue with its full length
  (`add_to_queue(afl, queue_fn, len, 0)`, line 615).
- **The bug:** AFL++ assumes no queue entry is over `MAX_FILE` (1 MiB, `afl/include/config.h:279`). Its own start-up
  path skips or truncates bigger files (`afl-fuzz-init.c:619`, `:809`) and skips empty ones (`:612`, `:802`); this
  path checks neither.
- **Found:** 2026-10-31, study 03, when campaigns ended `done (short)` because afl-fuzz itself segfaulted (the
  target didn't). Each time, it was fuzzing an in-run entry over 1 MiB ("after" is the job's run time, seed
  generation included):

  | Campaign | After | In-run entry being fuzzed |
  |---|---|---|
  | DeepSeek vorbis_decode_fuzzer-r2 | 2 h 07 | 1.41 MB `.ogg` |
  | DeepSeek libpcap_fuzz_both-r5 | 3 h 30 | 5.99 MB `.pcap` |
  | DeepSeek libpng_read_fuzzer-r4 | 3 h 13 | 1.44 MB `.png` |
  | DeepSeek vorbis_decode_fuzzer-r2, its retry | 3 h 29 | 1.32 MB `.ogg` |
  | Qwen libpcap_fuzz_both-r4 | 2 h 35 | 1.75 MB `.pcap`, just imported |
  | Llama libpng_read_fuzzer-r5 | 0 h 42 | 1.44 MB `.png` |
  | Llama libpng_read_fuzzer-r4 | 2 h 14 | 2.73 MB `.png` |
  | gpt-oss vorbis_decode_fuzzer-r5 | 2 h 28 | 6.91 MB `.rgb` |
  | Llama libpng_read_fuzzer-r5, its retry | 3 h 10 | 1.47 MB `.png` |
  | Llama vorbis_decode_fuzzer-r3, its retry | 2 h 29 | 1.92 MB `.wav`, one of six >1 MiB entries just imported |
  | phi-4 vorbis_decode_fuzzer-r3 | 2 h 31 | 6.00 MB `.wav` |
  | Seed-Coder vorbis_decode_fuzzer-r1 | 2 h 53 | 4.41 MB `.wav` |
  | Mistral libpng_read_fuzzer-r1 | 1 h 10 | 1.33 MB `.png` |
  | Mistral libpcap_fuzz_both-r1, its third run (the first two stopped on full disks, [OURS-3](#ours-3-output-on-the-nodes-shared-disk)) | 1 h 06 | 4.51 MB `.pcap` |
  | Mistral vorbis_decode_fuzzer-r3, its second run (the first stopped on a full disk) | 3 h 01 | 1.76 MB `.wav` |

  In-run entries are the queue files named `time:0,execs:<nonzero>,orig:...`. The first runs are kept in
  `experiments/03-model-sweep-qc/campaigns/.retried/`. afl-fuzz also stops on glibc heap checks (SIGABRT), sometimes
  in runs with no such entries: that's [G2F-3](#g2f-3-afl-fuzz-heap-corruption-in-g2fuzz-runs).

  This path also queues empty files, which AFL++'s start-up skips. No crash has been tied to them.
- **How often:** in-run entries over 1 MiB are common. By 2026-10-31 08:45 they were in 16 of 56 Llama campaigns,
  18 of 67 DeepSeek, 5 of 60 Qwen, 2 of 42 gpt-oss and 0 of 75 `afl` campaigns. Most of those finished normally (one
  Llama tiffsplit run had 26), so an oversized entry doesn't always cause a segfault. Big *initial* seeds are
  harmless: AFL++ truncates them at start-up.
- **Effect on results:** a crashed campaign stops fuzzing early, which lowers that model's coverage. It only happens
  with models whose generators write files over 1 MiB. Plain AFL++ never runs this path.
- **Status:** open. Not fixed mid-study: 03 and 04 run upstream's code (04 changes the time and where AFL++
  writes its output, not G2FUZZ). Each crashed campaign is run again once (03's analysis plan); one that crashes
  twice is excluded and listed.
  Four crashed on their retries too, so 03 excludes them: DeepSeek vorbis_decode_fuzzer-r2, Llama
  libpng_read_fuzzer-r5, Llama vorbis_decode_fuzzer-r3 (its first run hit G2F-3) and Mistral vorbis_decode_fuzzer-r3
  (its third run hit G2F-3; its first stopped on a full disk, which doesn't count).
  - 03 also reports a sensitivity analysis that keeps crashed runs at their coverage before the crash.
  - Candidate fix, for after 04: in `run_gen_seeds()`, skip files over `MAX_FILE` (or cap `len` at it) and empty
    files, as `read_testcases()` does. It may not fix G2F-3. It changes G2FUZZ's behaviour, so it starts a new study.

### G2F-2: `pip_debug` runs any answer as a pip command
- **Where:** `pip_debug_loop()` and `pip_debug()`, `g2fuzz/py_utils/func.py:496`.
- **The bug:** `extract_res_for_pip()` returns `(result, valid)`, where `result` is the command if `valid` and the
  problem otherwise. Upstream read it as `(code, msg)` and tested `code`, so every answer counted as a command and
  was run.
  - When no answer worked, it returned `None` to a caller that unpacks two values, a `TypeError`.
  - A pip timeout wasn't caught.
- **Found:** 2026-10-30, peer review before study 03.
- **Status:** fixed 2026-10-30 (255c12b, marked `BETTERG2FUZZ fix`): a bad answer is asked for again, and no usable
  answer returns cleanly. 01 ran without the fix. 03 and 04 have it.

### G2F-3: afl-fuzz heap corruption in G2FUZZ runs
- **Where:** not found. Only G2FUZZ arms have it, never the 75 plain `afl` campaigns, so it's most likely in what
  G2FUZZ adds to afl-fuzz: `run_gen_seeds()` and the LLM mutation step that calls it (`afl/src/afl-fuzz.c:3399`).
- **What:** glibc stops afl-fuzz (SIGABRT) on a corrupted heap: `free(): invalid pointer` or `invalid size`,
  `realloc(): invalid pointer` or `invalid old size`, `munmap_chunk(): invalid pointer`, `double free or corruption
  (out)`.
- **Found:** 2026-11-01, study 03, from how each campaign's `fuzz.log` ends. By 2026-11-01 21:30: 21 runs, 16 of
  them vorbis_decode_fuzzer (2 libpcap_fuzz_both, 1 each libpng_read_fuzzer, bloaty_fuzz_target and
  lcms_cms_transform_fuzzer); DeepSeek 5, Llama 4, Seed-Coder 4, Mistral 3, gpt-oss 2, phi-4 2, Qwen 1.
  - **5 mid-run**, so the campaign ended `done (short)`: DeepSeek vorbis_decode_fuzzer-r3 (3 h 18), Llama
    vorbis_decode_fuzzer-r3 (3 h 38), phi-4 vorbis_decode_fuzzer-r2 (4 h 19), Seed-Coder bloaty_fuzz_target-r5
    (2 h 53) and Mistral vorbis_decode_fuzzer-r3's third run (2026-11-01 19:31, 1 h 59; 1 h 35 of it fuzzing). The
    first three vorbis runs were each fuzzing a 64 KB in-run entry, a common size in vorbis queues; the bloaty run a
    120-byte one; Mistral's a 2.65 MB one (below).
  - **16 at exit**, after the full 6 h, while afl-fuzz frees its memory: DeepSeek libpcap_fuzz_both-r1 and -r2 and
    vorbis_decode_fuzzer-r3 (its retry) and -r5; gpt-oss vorbis_decode_fuzzer-r3 (its retry) and -r4; Llama
    libpng_read_fuzzer-r1 and vorbis_decode_fuzzer-r1 and -r5; Mistral vorbis_decode_fuzzer-r2 and -r5 (both their
    second runs, 2026-11-01); phi-4 lcms_cms_transform_fuzzer-r5; Qwen vorbis_decode_fuzzer-r1; Seed-Coder
    vorbis_decode_fuzzer-r1 (its third run, 2026-11-01), -r3 and -r4. Slurm
    shows them as `FAILED` (exit 134) or `OUT_OF_MEMORY`. They count as done: `fuzzer_stats` (run_time 21600) and the
    queue are written before the exit.
  - **In 04:** DeepSeek libpcap_fuzz_both-r1 stopped mid-run (2026-11-02 07:23, 4 h 07 of 24 h, `realloc(): invalid
    old size`; run again once). It was fuzzing a 30 KB entry made by AFL++'s own havoc stage, and G2FUZZ's last LLM
    step was 3 h 21 earlier, so the heap may have been damaged long before glibc noticed. In 03 DeepSeek's libpcap
    r1 and r2 both stopped this way at exit.
- **Not only G2F-1:** some of these runs had no in-run entries over 1 MiB and no empty ones (Qwen vorbis r1, gpt-oss
  vorbis r3 and r4). But Mistral vorbis_decode_fuzzer-r3's third run stopped (`realloc(): invalid pointer`) while
  fuzzing an entry its generator had just written at 2.65 MB (`ogg-30_1.ogg`; afl-fuzz had trimmed its queue copy
  to 12 KB). So some G2F-3 stops may be G2F-1's oversized entries, caught by glibc before they could segfault.
- **Effect on results:** a mid-run stop is handled like G2F-1's (run again once, listed). Stops at exit don't change
  the measured results. What the corruption did inside afl-fuzz before glibc caught it isn't known.
- **Status:** open, cause not found. Next step, after 04: run a G2FUZZ vorbis campaign with afl-fuzz built with ASan
  (AFL++'s `make ASAN_BUILD=1`), which reports the first bad write.

## AFL++ 4.32c (as vendored by G2FUZZ)

### AFL-1: afl-fuzz 4.32c fuzzes the CmpLog binary
- **Where:** `afl/src/afl-fuzz.c` (about line 2573). `check_binary()` for the `-c` CmpLog binary overwrites
  `afl->fsrv.target_path`, so both forkservers run the `.cmp` build. `ps` still shows the main target.
- **Found:** 2026-10-22, by checking `/proc/<pid>/exe` while fuzzing jhead. Introduced in 4.30c, fixed in 5.03c.
- **Effect on results:** every campaign (every G2FUZZ arm and the AFL++(cmplog) baseline) fuzzes the slower
  CmpLog-instrumented build. Comparisons inside a study stay fair. Absolute execs/s, and comparisons with other AFL++
  setups, don't. Upstream G2FUZZ ships the same AFL++, so the paper's runs likely had it too.
- **Status:** open, on purpose (01 `DRIFT.md` row 4.1). The backport is about 6 lines and needs an image rebuild,
  so it's for a new study only.

### AFL-2: afl-showmap 4.32c aborts on maps over 64K
- **Where:** `afl-showmap` 4.32c stops with `FS_ERROR_MAP_SIZE` when the target's map is over 64K and `AFL_MAP_SIZE`
  is unset. afl-fuzz 4.32c and afl-showmap 5.03c resize the map themselves.
- **Found:** 2026-10-22, on bloaty.
- **Status:** worked around. Every showmap-based tool (the targets test, coverage replay) sets
  `AFL_MAP_SIZE=2621440`, FuzzBench's value (01 `DRIFT.md` row 3.2).

## Our code

### OURS-1: UCB snapshot held one format's generators
- **Where:** `g2fuzz/py_utils/generator_scheduler.py` (the team's UCB generator scheduler, a174689). Its bookkeeping
  snapshot held only the generators passed to the current step. A pattern step passes one format's, so at the next
  step the other formats' generators looked new.
- **Found:** 2026-10-30, peer review before study 03.
- **Status:** fixed 2026-10-30 (255c12b): the snapshot covers every file in the generator folder. 03 and 04 have it.

### OURS-2: `scancel` skipped the study driver's cleanup
- **Where:** `scripts/study start --background`. The driver ran as `--wrap "<command>"`, so it was a child of the
  job's shell. `scancel` killed the job before the driver's EXIT trap could stop the LLM servers it had started.
- **Found:** 2026-10-30, testing before study 03 launched.
- **Effect:** none on results. A cancelled study left its servers running until their time limit.
- **Status:** fixed 2026-10-30 (`--wrap "exec <command>"`, verified with a test job). Uncommitted at the time of
  writing.

### OURS-3: output on the node's shared disk
- **Where:** `scripts/fuzz run`, in the `job.sbatch` it writes for each campaign. AFL++'s output folder is
  `${TMPDIR:-/tmp}/g2f-<job>` on the node, copied back to the campaign folder every 30 s and at the end. On Tempest's
  epyc nodes that's `/tmp`, one 893 GB disk shared by every job on the node, mostly other users'.
- **The bug:** nothing checks the free space or falls back to another disk. When the disk fills, every afl-fuzz on
  the node stops at once: `Unable to create '<output>/default/.cur_input'` (or a new queue file), `No space left on
  device`, exit 1.
- **Found:** 2026-11-01, study 03. 10 campaigns ended `done (short)` this way, on three nodes: epyc023 at 03:03
  (gemma sndfile_fuzzer-r2), epyc014 at 03:23 (gemma sndfile_fuzzer-r3 and -r4, phi-4 sndfile_fuzzer-r2 to -r4,
  phi-4 vorbis_decode_fuzzer-r3's retry, Seed-Coder sndfile_fuzzer-r1) and epyc019 at 03:26 (Seed-Coder
  bloaty_fuzz_target-r1 and -r2).
  - 20 more from 04:15 to 05:31, one node after another: epyc014 (04:15), epyc012 (04:25), epyc017 (04:44 and
    04:59), epyc013 (05:10) and epyc015 (05:31). Mostly Mistral and Seed-Coder, on libpcap_fuzz_both, pdftotext,
    freetype2_ftfuzzer, bloaty_fuzz_target, sndfile_fuzzer and vorbis_decode_fuzzer. Two were reruns: Seed-Coder
    bloaty_fuzz_target-r2 (stopped at 03:26 by the full disk) and vorbis_decode_fuzzer-r1 (by G2F-1). 19 ended
    `done (short)`. Seed-Coder mp42aac-r5 stopped at 5 h 49 of fuzzing and counts as done.
  - At 06:10, `/tmp` on the 10 epyc nodes running our campaigns was 86–99% full and losing up to about 80 GB an
    hour (epyc009: 254 GB free at 03:55, 70 GB at 06:10). One node, epyc012, had gained space.
  - 19 more from 06:16 to 07:12: epyc023, epyc016, epyc009 and epyc015 again. 9 of them were reruns of the first
    10, including all 7 sndfile reruns (epyc009 at 06:48). That makes 49 stops on nine nodes by 07:15.
  - One more stopped later. Seed-Coder bloaty_fuzz_target-r2's rerun wrote queue entry `id:002194` about 05:09, as
    epyc013's disk filled. The file came out short, and afl-fuzz stopped when it read it back about 25 min later:
    `Short read from .../queue/id:002194`.
  - 6 more from 07:30 to 07:56 on epyc013, epyc016 and epyc014, including phi-4 vorbis_decode_fuzzer-r3's third run.
    That makes 56 stops by 08:15.
  - One more at 09:33 on epyc014 (Mistral vorbis_decode_fuzzer-r5, after 5 h 7 min), with only 14 of ours left
    running: 57 stops by 10:20. At 10:20 epyc013's disk was full (812 KB free) and a minute later had 71 GB; the 9
    of ours there kept running. Another at 11:34 there, Mistral pdftotext-r2's rerun 54 min in (the other
    4 of ours kept running): 58 by 11:50.
  - 5 more at 12:08 on epyc011, all reruns early in their fuzzing; an `osg01` pilot there ended 17 s later. That
    makes 63 stops on ten nodes by 12:15.
  - 3 more at 12:30 on epyc019 (Mistral pdftotext-r3 to -r5's reruns); an `osg01` pilot there ended the same
    second. 66 by 12:35. So the fills aren't one episode: none in 03's first 31 h, then steadily from 03:00 to at
    least 12:30.
  - 3 more at 13:00 on epyc022, all libpcap_fuzz_both reruns (Mistral -r1 and -r2, Seed-Coder -r2), our only
    jobs there. No other job there ended around then. 69 stops on eleven nodes by 13:05.
  - 2 more at 14:16 on epyc011 again (phi-4 sndfile_fuzzer-r5 and Mistral libpcap_fuzz_both-r5, reruns); an
    `osg01` pilot there ended 4 s later. 71 by 14:20.
  - 2 more at 16:33 on epyc019 (Mistral libpcap_fuzz_both-r4 and sndfile_fuzzer-r2, reruns). The sndfile job was
    then killed for memory (`OUT_OF_MEMORY`), 56 s after its afl-fuzz had stopped; its output was 248 MB. No other
    job there ended around then. 73 by 16:40.
  - It isn't our jobs. They had at most 6 GB of files in each node's `/tmp`, and no deleted files held open
    anywhere, the output folder included (checked again at 07:15 on all nine nodes). The libpcap target writes about
    133 GB over a run, but in small temp files it removes after each execution. Free space also swings on nodes where
    none of ours stopped: epyc017 went from 14 GB to 186 GB in an hour. When a disk fills, the other jobs there stop
    too, and their space comes back.
  - Checked again over all 23 fills to 16:33 (at 17:00). G2FUZZ's in-run generators write into the output's
    `default/tmp/` and then empty it, so one could fill a disk and free it again. But in 12 of the fills none of our
    campaigns on that node had run one in the 15 min before. The output is copied back every 30 s, `default/tmp/`
    included, and the largest file any generator wrote, in all 691 campaigns, is 3.3 GB. At 16:33 on epyc019 our
    three campaigns held about 260 MB, and the disk had 223 GB free a few minutes later.
  - The timing points to the Open Science Grid's pilot jobs (`osg01`, account `group-osg`). 616 were running at
    08:00, 20 to 30 on each epyc node, each with a private folder in `/tmp`. They're listed by `sacct -a`, not by
    `squeue`. In 7 of the 13 fills one of them ended within 40 s of ours. On epyc015 at 07:12, three ended together,
    and free space went from 29 MB to 211 GB. Their folders can't be read, so their sizes aren't known.
  - At 17:00 there were 926 pilots, 909 of them in Tempest's `osg-epyc` partition: 8 CPUs each, 25 to 48 per
    epyc node. OSG asks sites for 2 GB of scratch per core at least and 10 GB recommended
    ([Worker Node Overview](https://osg-htc.org/docs/worker-node/using-wn/)). That's 400 GB to 3.8 TB per node at
    these counts, against `/tmp`'s 893 GB. The same page warns that if many pilots "do not exit cleanly (e.g., due
    to preemption), this may result in the local scratch directory filling up, which could negatively affect other
    jobs running on the impacted node".
  - No `seedgen.log` has a disk error, so none of the `no seeds` cells comes from this.
  - G2FUZZ adds to it. One phi-4 sndfile generator wrote a 1.8 GB `track1.wav` into the output's `default/tmp/`.
    Generators run in the container with the node's `/tmp` bound in, and leave files there that nothing removes. On
    epyc014 that was about 6 GB (2,046 entries): Python temp folders (some holding a 201 MB static ffmpeg download),
    temp `.py` scripts and `libpcap_fuzz_both.*` files. On 2026-11-01 at 07:10 we deleted those unchanged for
    12 h: 4,535 entries, 10 GB, on eight nodes.
- **Effect on results:** a stopped campaign fuzzes for less time. The stop depends on the node, not the arm.
- **Status:** worked around for 04; 03 keeps its setup to the end. A campaign stopped this way is run again;
  it isn't a crash, so it doesn't count toward the two-failure limit (phi-4 vorbis_decode_fuzzer-r3 was on its
  second run). From 06:15 the reruns waited for free space: Slurm places a rerun where a stopped campaign freed its
  CPUs, which is the full node, and two reruns stopped again that way. The disks hadn't settled by 10:40, but stops
  had become rare, so the 46 stopped by then were moved aside at 10:40 and run again with the same setup; one that
  stops again gets another run. 04's start job is held until they finish.
  - For 04 (2026-11-01, before launch): `output = campaign` in its `study.conf` (`scripts/fuzz`'s
    `G2F_OUTPUT=campaign`; the default, `node`, is unchanged). AFL++ writes its output straight into the campaign
    folder, and the file the target reads (`.cur_input`, rewritten for every execution: the reason for the node disk)
    into the job's memory folder `/dev/shm/jobs/<job>` (`AFL_TMPDIR`). So afl-fuzz no longer writes to the node disk.
    At 03's rate (one stop per 8.5 campaign-hours since the fills began), only 6% of 24 h runs would have finished
    uninterrupted. A side-by-side test found no speed difference (04's README).
  - Still on the node disk: the libpcap target's temp files and the generators' temp files in `/tmp`. A fill would
    make those writes fail, but afl-fuzz itself doesn't write there.
  - Candidate fix, for after 04: also check the free space at job start, give the container its own `/tmp` inside
    the job's folder, and remove it at the end. Tempest makes `/tmp/jobs/<job>` and `/dev/shm/jobs/<job>` for every
    job and removes them when it ends; the second is in memory and counts against the job's. All of the output in
    `/dev/shm` was considered for 04 and not done (2026-11-01): see its README.

## Not bugs: failures that look like them
- **A seed that times out stops AFL++.** If one initial seed takes over 1000 ms in afl-fuzz's start-up check,
  AFL++ (4.32c and 5.03c) aborts. That's by design; `AFL_IGNORE_SEED_PROBLEMS=1` skips the seed instead, and our
  studies don't set it.
  - Seen in 01 (`B-mp42aac-g2503-r3`, `DRIFT.md` row 5.7) and in 03: Llama `imginfo-r2` (2026-10-30) and `sndfile_fuzzer-r3`
    (2026-10-31; both then ended `OUT_OF_MEMORY`), gpt-oss `vorbis_decode_fuzzer-r3` and Llama `libpng_read_fuzzer-r3`
    (2026-10-31); in 04: Qwen `mp42aac-r3` (2026-11-02, a 2.3 MB generated `.mp4`).
  - Each counts as a failure: the campaign is run again once (with new seeds, since each run generates its own).
- **`OUT_OF_MEMORY` on runs that finished.** 9 in 03: DeepSeek mp3gain-r5, Llama mp3gain-r1, -r3, -r5 and
  sndfile_fuzzer-r4, Mistral tiffsplit-r4 and -r5 and sndfile_fuzzer-r5 (its second run, 2026-11-01), and phi-4
  vorbis_decode_fuzzer-r2's retry. afl-fuzz fuzzed the
  full 6 h and ended normally ("We're done here"). Slurm logged an `oom_kill` of some process in the job (which one
  isn't recorded: a generator script or the target reaching the job's 8 G), so the job shows as `OUT_OF_MEMORY`.
  Results unaffected.
- **A target corrupts the coverage map.** AFL++ aborts with `Incorrect fuzzing setup detected`. Seen once:
  01 `C-exiv2-afl432-r3` (`DRIFT.md` row 5.11).
- **`Bus error (core dumped)` from afl-fuzz** when an `--afl` run was stopped about 66 s in. Seen once (2026-10-29);
  its stats and copy-back were fine.
