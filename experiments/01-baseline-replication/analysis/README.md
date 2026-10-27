# Analysis: phase B

Turns `campaigns/B-*` into `results/`. Three steps, run in order from this folder on Tempest. Damaged runs
(`*.damaged-*`) are skipped everywhere (`campaigns.sh` decides which campaigns count).

| Step | What | Runs as | Writes |
| --- | --- | --- | --- |
| `01-coverage.sbatch` + `coverage_aggregate.py` | Replays every final queue on ONE common binary (4.32c `.afl`, `afl-showmap` 4.32c, `AFL_MAP_SIZE=2621440`); edges at the end, from the initial seeds alone, and every 15 min | Slurm array, 1 task per campaign (1 CPU, 4 GB) | `results/coverage/<c>.json`, `results/coverage/edges/<c>.txt.gz` |
| `02-crashes.sbatch` + `crash_triage.py` | Reruns every saved crash on the `.asan` build; buckets by bug type + top 3 ASan frames (UNIFUZZ's rule) | Slurm array, 1 task per campaign (1 CPU, 8 GB) | `results/crashes/<c>.tsv`, `results/crashes/<c>.json` |
| `03-stats.py` | Per-campaign table (execs/s, LLM calls/steps, seed generation time, ...), per program x arm medians + IQR, exact Mann-Whitney U and Vargha-Delaney A12, report | Python 3 anywhere (login node is fine; pure Python) | `results/campaigns.tsv`, `by-arm.tsv`, `tests.tsv`, `REPORT.md` |

```bash
cd experiments/01-baseline-replication/analysis
bash submit.sh 01            # coverage; add sbatch options after the step, e.g. --partition=priority --account=...
bash submit.sh 02            # crashes (independent of 01; can run at the same time)
python3 03-stats.py          # after both arrays finished; rerun any time
```

Phase C: prefix every command with `G2F_PHASE=C` (campaigns.sh then lists `C-*`, the arrays and `03-stats.py` write
into `results/phase-C/`; each campaign's own `-V` from its run.sh is the "complete" threshold and the end of the
edges-over-time buckets).

Checks: `grep -L done logs/coverage-*.out` lists tasks that did not finish; a single campaign is redone with
`sbatch --array=<index> 01-coverage.sbatch` (index = its line in `bash campaigns.sh`, counted from 0).

Replication check: `paper-table1.tsv` holds the paper's Table 1 (Cov. and #Bug for G2FUZZ(GPT-3.5), G2FUZZ(GPT-4)
and AFL++(cmplog), copied from the arXiv PDF with pdftotext); `03-stats.py` compares the sign of
G2FUZZ - AFL++(cmplog) per program, AFL++ version and metric against each paper column.
Sensitivity: campaigns flagged `fix-a` in `campaigns.tsv` (DRIFT.md 5.7) are repeated without in `tests-excl-flagged.tsv`;
`unique_bugs_fn` is the coarser function-names-only bucket count next to the UNIFUZZ rule's `unique_bugs`.
Second triage rule (2026-10-25): `CAP=1 bash submit.sh 02 ...` reruns step 2 with ASan's allocation cap at 1 GB
(`max_allocation_size_mb=1024:allocator_may_return_null=0`) into `results/crashes-cap1g/`; an allocation over 1 GB then
reports as `allocation-size-too-big`, which is what `afl-fuzz -m 1024` saved as a crash. `03-stats.py` reports it as
`unique_bugs_cap` / `bugs_cap_med` next to the strict rule and tests it too.

Why one common binary: edge ids differ between AFL++ 4.32c and 5.03c builds, so each arm's own `edges_found` only
compares within an arm. Replaying all queues on the 4.32c binary measures the same thing for all four arms.
The replay uses the campaigns' own limits (`-m 1024`, like `afl-fuzz`), so inputs behave as they did while fuzzing.
Caveats recorded by the scripts: inputs that time out in the replay (`not_replayed`), inputs over 1 MB
(`afl-showmap` reads the first 1 MB), crashes that do not reproduce on the ASan build (`no-crash`), crashes whose
ASan run is killed by the kernel (`signal:9`, usually memory: AFL++'s `-m 1024` counted those as crashes, ASan has
no such limit) or hangs (`timeout`).
