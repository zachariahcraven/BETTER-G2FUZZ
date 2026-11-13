# 05 Model sweep on quantumcore, 24 h, no scheduler

**Question:** what does this repo's `ucb` generator scheduler contribute? [04](../04-model-sweep-qc-24h/README.md)'s
study run again with one change: the `random` generator scheduler (upstream G2FUZZ's pick) in place of `ucb`. Because
the models, target builds, image, hardware, reps and time are all 04's, 05 vs 04 is a direct per-cell comparison of
code coverage and unique bugs, and 05 is a scheduler-off baseline for 04 that needs no comparison to the paper.
**Owner:** n59m742. **Status:** campaigns finished; analysis to do (launched 2026-11-07 16:04 by driver job 1116675, which ended
2026-11-12 14:30, all 675 finished). **Started:** 2026-11-07.

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
  `campaigns/.retried/`); a campaign that fails twice is excluded and listed.
  Excluded: DeepSeek-Coder-V2-Lite-Instruct/libpcap_fuzz_both-r2 and -r5, Qwen3.8-27B-FP8/vorbis_decode_fuzzer-r4,
  Llama-3.1-8B-Instruct/vorbis_decode_fuzzer-r4, phi-4/bloaty_fuzz_target-r4 and vorbis_decode_fuzzer-r4, and
  Seed-Coder-8B-Instruct/bloaty_fuzz_target-r1 and vorbis_decode_fuzzer-r2
  ([G2F-1](../../docs/KNOWN_BUGS.md#g2f-1-in-run-seeds-skip-afls-size-checks) twice each, except DeepSeek libpcap r2: [G2F-3](../../docs/KNOWN_BUGS.md#g2f-3-afl-fuzz-heap-corruption-in-g2fuzz-runs) twice, and phi-4 vorbis r4 and Seed-Coder bloaty r1: G2F-3 then G2F-1;
  2026-11-08 to 12). The upstream G2FUZZ crashes
  ([G2F-1](../../docs/KNOWN_BUGS.md#g2f-1-in-run-seeds-skip-afls-size-checks),
  [G2F-3](../../docs/KNOWN_BUGS.md#g2f-3-afl-fuzz-heap-corruption-in-g2fuzz-runs)) and the libpcap memory kills
  ([OURS-4](../../docs/KNOWN_BUGS.md#ours-4-the-kernels-file-name-cache-counts-against-a-campaigns-memory)) recur, with
  04's rerun rules. New in 05: a transient NFS error stopping afl-fuzz
  ([OURS-5](../../docs/KNOWN_BUGS.md#ours-5-a-transient-nfs-error-stops-afl-fuzz)): run again, not counted.

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
- **Campaigns finished 2026-11-12 14:30** (driver job 1116675; launched 2026-11-07 16:04). Of the 675 campaigns, 649
  fuzzed the full 24 h, 18 made no seeds (their result: DeepSeek freetype2 r1, r3 and r5, mp42aac r4 and woff2 r1,
  r2, r4 and r5; gemma mp42aac r1; Llama woff2 r3 and r5; Mistral freetype2 r1, r2 and r5; phi-4 freetype2 r1 and
  r3; Seed-Coder freetype2 r5 and mp42aac r1) and 8 are excluded (Analysis plan, Failures). 28 runs were moved
  aside and run again (`campaigns/.retried/MOVED.txt`): 21 counting failures (16 [G2F-1](../../docs/KNOWN_BUGS.md#g2f-1-in-run-seeds-skip-afls-size-checks), 4 [G2F-3](../../docs/KNOWN_BUGS.md#g2f-3-afl-fuzz-heap-corruption-in-g2fuzz-runs), 1 generated seed that timed out in afl-fuzz's dry run) and 7 that
  don't count (6 libpcap memory kills, [OURS-4](../../docs/KNOWN_BUGS.md#ours-4-the-kernels-file-name-cache-counts-against-a-campaigns-memory); 1 NFS error,
  [OURS-5](../../docs/KNOWN_BUGS.md#ours-5-a-transient-nfs-error-stops-afl-fuzz)). 32 runs that fuzzed the full
  24 h then aborted in glibc as afl-fuzz exited (G2F-3; 19 in 04), and 12 ended `OUT_OF_MEMORY` after fuzzing the
  full 24 h or, for Qwen libpcap r2, 23 h 10 of it (`docs/KNOWN_BUGS.md`, "Not bugs" and OURS-4; Llama vorbis r5
  is in both lists); all count as done.
- Every campaign, crash, hang and rerun, with the column key: `results/05-model-sweep-qc-24h-nosched.xlsx`
  (`scripts/results-xlsx 05-model-sweep-qc-24h-nosched --inputs`, which also packs the crashing inputs for a GitHub
  release).
- **First look, 05 vs 04** (the Analysis plan's tests are still to do): per model and target, the median `edges`
  over the campaigns that fuzzed the full 24 h, 05's as a fraction of 04's, from both studies' `results/*-r1-5.csv`.
  The `afl` arm is the same design in both studies, so its row shows the between-study noise. Crashes are the
  inputs AFL++ saved, summed over the full-length campaigns (several can be one bug).

**Per target: 05 median edges / 04 median edges (campaigns that fuzzed the full 24 h; `-`: no full run in one study)**

| Target | afl | DeepSeek | gpt-oss | Qwen | Llama | gemma | phi-4 | Mistral | Seed-Coder |
|---|---|---|---|---|---|---|---|---|---|
| bloaty_fuzz_target | 1.00 | 1.00 | 0.99 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.01 |
| freetype2_ftfuzzer | 1.01 | 0.97 | 1.02 | 1.00 | 0.97 | 1.00 | 0.92 | 1.04 | 1.00 |
| gdk-pixbuf-pixdata | 0.99 | 1.02 | 1.00 | 1.01 | 1.00 | 0.99 | 1.00 | 1.00 | 0.97 |
| imginfo | 1.00 | 1.00 | 1.59 | 1.00 | 1.09 | 1.00 | 1.00 | 1.00 | 1.00 |
| jhead | 1.00 | 1.00 | 1.00 | 1.02 | 1.00 | 0.99 | 1.00 | 1.00 | 0.99 |
| lcms_cms_transform_fuzzer | 0.95 | 0.84 | 1.24 | 0.71 | 1.03 | 1.04 | 0.46 | 1.01 | 0.88 |
| libpcap_fuzz_both | 0.99 | 1.06 | 0.95 | 1.00 | 1.00 | 1.06 | 0.86 | 0.98 | 0.93 |
| libpng_read_fuzzer | 1.00 | 1.00 | 0.99 | 1.00 | 1.01 | 1.01 | 1.00 | 1.01 | 1.01 |
| mp3gain | 1.00 | 1.00 | 0.99 | 0.99 | 1.01 | 1.00 | 1.00 | 0.99 | 1.00 |
| mp42aac | 0.98 | 0.99 | 1.04 | 0.80 | 1.00 | 0.89 | 0.96 | 0.92 | 0.96 |
| pdftotext | 1.09 | 1.12 | 1.03 | 1.02 | 0.97 | 0.92 | 0.95 | 0.86 | 0.99 |
| sndfile_fuzzer | 0.99 | 1.00 | 1.04 | 1.03 | 0.98 | 1.00 | 0.99 | 1.00 | 1.02 |
| tiffsplit | 1.00 | 1.01 | 1.02 | 0.98 | 0.99 | 1.02 | 0.98 | 1.00 | 0.98 |
| vorbis_decode_fuzzer | 1.00 | 0.99 | 1.00 | 1.00 | 0.99 | 1.00 | 1.00 | 1.00 | 1.01 |
| woff2_convert_woff2ttf_fuzzer | 1.00 | 0.93 | 1.00 | 1.00 | 1.06 | 1.00 | 1.02 | 1.00 | 1.00 |

**Per model: targets compared, 05 above / below 04, median ratio, crashes saved (04 -> 05), no-seeds cells (04 -> 05)**

| Model | Targets | 05 > 04 | 05 < 04 | Median 05/04 | Crashes 04 | Crashes 05 | No seeds 04 | No seeds 05 | Short 04 | Short 05 |
|---|---|---|---|---|---|---|---|---|---|---|
| afl | 15 | 6 | 9 | 1.00 | 4338 | 4782 | 0 | 0 | 0 | 0 |
| DeepSeek | 15 | 7 | 7 | 1.00 | 4661 | 4941 | 4 | 8 | 0 | 2 |
| gpt-oss | 15 | 10 | 5 | 1.00 | 6329 | 6446 | 0 | 0 | 0 | 0 |
| Qwen | 15 | 6 | 8 | 1.00 | 5476 | 5511 | 0 | 0 | 3 | 1 |
| Llama | 15 | 7 | 7 | 1.00 | 4919 | 4289 | 1 | 2 | 0 | 1 |
| gemma | 15 | 5 | 8 | 1.00 | 5141 | 4769 | 1 | 1 | 0 | 0 |
| phi-4 | 15 | 6 | 9 | 1.00 | 4697 | 5061 | 4 | 2 | 0 | 2 |
| Mistral | 15 | 5 | 9 | 1.00 | 4696 | 3917 | 4 | 3 | 2 | 0 |
| Seed-Coder | 15 | 7 | 8 | 1.00 | 5147 | 3897 | 4 | 2 | 3 | 2 |

**Per target, both studies: median edges per model (04 / 05)**

| Target | afl | DeepSeek | gpt-oss | Qwen | Llama | gemma | phi-4 | Mistral | Seed-Coder |
|---|---|---|---|---|---|---|---|---|---|
| bloaty_fuzz_target | 8600 / 8630 | 8667 / 8677 | 8738 / 8671 | 8707 / 8699 | 8689 / 8731 | 8693 / 8676 | 8630 / 8663 | 8666 / 8640 | 8585 / 8657 |
| freetype2_ftfuzzer | 8975 / 9054 | 8677 / 8376 | 9380 / 9535 | 9326 / 9293 | 8906 / 8608 | 8679 / 8674 | 9578 / 8802 | 9161 / 9504 | 8963 / 8973 |
| gdk-pixbuf-pixdata | 2120 / 2095 | 2211 / 2255 | 2226 / 2230 | 2184 / 2200 | 2197 / 2191 | 2202 / 2177 | 2223 / 2226 | 2235 / 2228 | 2251 / 2194 |
| imginfo | 2107 / 2100 | 2089 / 2098 | 2113 / 3352 | 2108 / 2107 | 1930 / 2102 | 2114 / 2107 | 2107 / 2105 | 2109 / 2105 | 2108 / 2100 |
| jhead | 619 / 617 | 621 / 621 | 664 / 666 | 610 / 620 | 567 / 566 | 626 / 622 | 623 / 626 | 626 / 626 | 627 / 622 |
| lcms_cms_transform_fuzzer | 1519 / 1441 | 1516 / 1274 | 1184 / 1463 | 1644 / 1166 | 658 / 678 | 1474 / 1537 | 1541 / 714 | 1562 / 1575 | 1500 / 1314 |
| libpcap_fuzz_both | 1851 / 1825 | 1810 / 1927 | 2220 / 2114 | 2119 / 2119 | 2121 / 2124 | 2161 / 2280 | 2244 / 1932 | 2096 / 2060 | 2060 / 1916 |
| libpng_read_fuzzer | 1571 / 1575 | 1572 / 1574 | 1585 / 1567 | 1562 / 1566 | 1542 / 1551 | 1555 / 1569 | 1565 / 1568 | 1557 / 1579 | 1565 / 1576 |
| mp3gain | 879 / 875 | 881 / 878 | 903 / 898 | 892 / 882 | 894 / 900 | 882 / 882 | 883 / 879 | 880 / 875 | 876 / 878 |
| mp42aac | 1258 / 1233 | 1301 / 1285 | 2031 / 2108 | 1977 / 1590 | 1415 / 1415 | 1486 / 1317 | 1272 / 1222 | 1332 / 1228 | 1370 / 1317 |
| pdftotext | 5561 / 6043 | 5897 / 6595 | 6500 / 6673 | 6338 / 6445 | 6844 / 6649 | 6594 / 6065 | 6760 / 6401 | 6829 / 5891 | 6070 / 6033 |
| sndfile_fuzzer | 3418 / 3385 | 3394 / 3388 | 3420 / 3549 | 3388 / 3480 | 3481 / 3427 | 3387 / 3375 | 3457 / 3409 | 3406 / 3398 | 3420 / 3484 |
| tiffsplit | 1761 / 1758 | 1803 / 1826 | 1884 / 1916 | 1842 / 1809 | 1833 / 1808 | 1834 / 1869 | 1873 / 1843 | 1840 / 1846 | 1875 / 1830 |
| vorbis_decode_fuzzer | 1069 / 1072 | 1078 / 1070 | 1097 / 1098 | 1086 / 1088 | 1085 / 1078 | 1096 / 1101 | 1088 / 1089 | 1085 / 1088 | 1069 / 1079 |
| woff2_convert_woff2ttf_fuzzer | 2392 / 2400 | 2550 / 2374 | 2549 / 2539 | 2404 / 2402 | 2400 / 2545 | 2402 / 2402 | 2477 / 2523 | 2409 / 2406 | 2382 / 2393 |
