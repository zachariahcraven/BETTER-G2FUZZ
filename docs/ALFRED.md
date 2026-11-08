# Alfred

Alfred started 2026-11-07 as a copy of BETTERG2FUZZ (`students/alfred`, git branch `alfred`). Both can run
studies at the same time without touching each other (next section). What Alfred changes is in
[How Alfred runs G2FUZZ](#how-alfred-runs-g2fuzz).

## Separate
| What | BETTERG2FUZZ | Alfred |
|---|---|---|
| Repo, image (`build/g2fuzz.sif`) | `students/BETTERG2FUZZ` | `students/alfred` |
| Targets (build-paper.sh writes, study reads `paper/`) | `students/g2f-targets` | `students/g2f-targets-alfred` |
| Campaign jobs | `g2f-<campaign>` | `alfred-<campaign>` |
| Study drivers | `study-<study>` | `alfred-study-<study>` |
| LLM servers (found by job name) | `llm-serve` | `alfred-llm-serve` |
| LLM logs and key | `~/llm` | `~/llm-alfred` |
| Image and target builds | `g2f-image`, `g2f-build-*` | `alfred-image`, `alfred-build-*` |
| Docker tags on the Mac | `g2fuzz:amd64`, `g2f-builder:*` | `alfred:amd64`, `alfred-builder:*` |
| Shell alias (scripts/enable-completion) | `fuzz` | `alfred` |
| `scripts/tempest-image` uploads to | `students/BETTERG2FUZZ` | `students/alfred` |
| `scripts/group-perms` default | the students folder | this repo |
| git remote | `origin` | `betterg2fuzz` (push Alfred as branch `alfred`; never merge it into `dev`) |

`scripts/fuzz llm stop` only counts this repo's campaigns as using a server. BETTERG2FUZZ's version counts Alfred's
campaigns too, so it may refuse to stop one of its servers while an Alfred campaign of that model runs (safe side).

## Still shared
- `students/shared-models` (model weights, read only; `scripts/fetch-models` adds to it) and `~/.secrets`.
- The Slurm accounts and their limits (e.g. priority-quantumcore: 4 GPUs), so the two projects queue behind each
  other. Plan GPU studies around each other.
- The same Unix user: `scancel -u $USER` stops both projects' jobs. Stop one project's jobs by name instead:
  `squeue -h -u $USER -o "%i %j" | awk '$2 ~ /^alfred-/ {print $1}' | xargs -r scancel`
- Environment variables keep their `G2F_` names: set them per command, not in `~/.bashrc`.

## g2f-targets-alfred
`paper/` and `latest/` were copied from `students/g2f-targets` on 2026-11-07 (AFL++ 4.32c, LLVM 16). They predate the
AFL++ 5.03c upgrade below and must be rebuilt with it before Alfred's results count (AFL++ 5.02c: persistent-mode
and `LLVMFuzzerTestOneInput` targets need recompiling). It has no builder images yet, so `build-paper.sh` stops until
Alfred's own builders exist.

## How Alfred runs G2FUZZ
Since 2026-11-08. Upstream G2FUZZ (and BETTERG2FUZZ) run a patched AFL++ 4.32c: when coverage stalls, afl-fuzz itself
stops, runs `python generator_mutation.py` with `system()`, then copies every file the generators wrote straight into
its queue and fuzzes each at once. Alfred instead:

- **AFL++ 5.03c, unpatched, LLVM 18** (`afl/` is the v5.03c release minus its dot files; `build/Dockerfile.g2fuzz`
  stays on Ubuntu 22.04 and its Python 3.10, with LLVM 18 from apt.llvm.org). Both arms run the same afl-fuzz
  command: no `-M`/`-S` (afl-fuzz sets itself up as `-S default`), `AFL_SYNC_TIME=1`, `AFL_IGNORE_SEED_PROBLEMS=1`.
- **The LLM side is a separate process,** `g2fuzz/llm_worker.py`, started by run.sh just before afl-fuzz (G2FUZZ
  arms only). It runs the same `generator_mutation.py` and writes the seeds to `<target>_output/llm/queue/` as
  `id:N,orig:<seed>`. That folder is a fuzzer instance as far as AFL++ is concerned (it holds `is_main_node`), so
  afl-fuzz imports from it at its next sync (the worker sends SIGUSR2 to sync at once). Fuzzing never pauses.
- **When a step runs** (`G2F_LLM_MODE`): `stall` (default) is upstream's trigger: 300 s without a new queue entry and
  since the last step, +60 s per step taken (`G2F_PLATEAU_SEC`, `G2F_BACKOFF_SEC`; `--test` sets 10 and 0).
  `continuous` runs one step after another (`G2F_LLM_GAP_SEC` apart).
- **Logs:** `llm-worker.log` in the campaign folder (`==== Gen-M start/end ====` per step; `watch`, `results` and
  `scripts/study results` count these), `<target>_output/llm/steps.jsonl` (one line per step: time, exit status,
  seeds), and `gen_seeds_energy_log`/`mutate_log` as before.
- **Lineage:** AFL++ names an imported seed `id:N,sync:llm,src:M` (M: the worker's id). `g2fuzz/py_utils/lineage.py`
  maps it back to `orig:<seed>`, so the UCB scheduler and the pattern mutator credit the right generator.

### What that changes in the results (compare with upstream/BETTERG2FUZZ studies with care)
- **Only seeds that reach new coverage enter the queue.** AFL++ runs each synced seed and keeps it if it is
  interesting (`save_if_interesting`), like any synced input; upstream added every seed and fuzzed each one first.
  A generator whose seeds add nothing now leaves no queue entry, so the UCB scheduler counts it as a failure.
  `scripts/study results` has two new columns: `llm_seeds` (handed to AFL++) and `llm_kept`.
- **Seeds get AFL++'s checks:** empty and over-1-MiB files are never imported (upstream's in-run path skipped
  these checks: G2F-1). The worker drops them and counts them in `steps.jsonl`.
- **No `-M`.** AFL++'s `-F` foreign-sync option would also do this, but it needs `-M`, and in 5.03c `-M` switches the
  main fuzzer to the old queue walk and turns trimming off. The baseline would then have to run differently, or the
  arms would differ in more than the LLM.
- **LLM time no longer counts against fuzzing.** Upstream's `-V` included the time afl-fuzz waited for the LLM
  (0.15–1.7% of the run in 03/04); the worker runs on the campaign's second CPU.
- **libpcap_fuzz_both gets 16G** unless `G2F_MEM` is set (OURS-4: the kernel's cache of its temp files reached the
  8G limit in 4–16 h in 04's G2FUZZ arms). This is more headroom, not a fix.

### Tests
- `python3 g2fuzz/tests/test_llm_worker.py`: the worker's trigger, backoff, continuous mode, hand-over (ids in order,
  size checks, file names), stopping with afl-fuzz, and the lineage rewrite. No AFL++, GPU or LLM; runs on a Mac or in
  the image.
- `scripts/tests/test_fuzz_cli.sh`: contracts for the worker in run.sh, the same afl-fuzz settings in both arms,
  `G2F_LLM_MODE`, the 16G for libpcap, and `status`/`results` of a worker campaign.
- End to end (2026-11-08, `alfred:test-amd64` on the Mac, jhead, 2 min, a stand-in step writing JPEG variants instead of
  the LLM): afl-fuzz 5.03c reported `autoconfiguring for "-S default"`, the worker handed over 24 seeds in 8 steps,
  AFL++ kept 2 (`id:000073,sync:llm,src:000004` and `id:000074,sync:llm,src:000009,+cov`), lineage mapped them to
  `jpg-21` and `jpg-23`, and the worker exited with afl-fuzz.
