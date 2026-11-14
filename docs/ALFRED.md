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

## Tweak switches, rounds and their tools (2026-11-09)
Alfred improves in 6 h rounds ([ALFRED-ROUNDS.md](ALFRED-ROUNDS.md): the acceptance rule, the switches, the backlog
and the rounds log).
- **Switches:** `scripts/fuzz run --set NAME=VALUE`, or a study arm's `set:NAME=VALUE`.
  - `scripts/fuzz tweaks` lists the allowed names, values and when each acts.
  - A campaign records its switches in its `tweaks` file, which `status` and `results` print, and `launch.txt` has
    them too.
  - A setup switch needs seed generation, so `scripts/study` refuses it with shared or reused seeds.
- **New switches:**
  - `G2F_STALL_MUTATORS` (the `rare` stall mutator, in `generator_mutation.py`).
  - `G2F_RFDM_ALL_FORMATS` (in `program_gen.py`).
  - Together with the worker's existing `G2F_LLM_MODE`, `G2F_PLATEAU_SEC` and `G2F_BACKOFF_SEC`.
- **What `program_gen.py` and the worker now record:**
  - `program_gen.py` also writes each format's own `feature_pool-<format>.json`.
  - The worker records each step's mutator and new generator in `llm/steps.jsonl`.
- **`scripts/compare <study>`:**
  - The rule's decisions; per target, medians, A12 and exact Mann–Whitney p.
  - LLM use, kept seeds per mutator, and failures and bug signs.
  - The failure signs: aborts and heap errors at the end of `fuzz.log`, worker tracebacks, OOM kills, and queue files
    over 1 MiB.
  - Plain Python 3, no scipy.
- **`scripts/lineage <study>`:**
  - Each queue entry is traced to its root seed: stock, setup round 0, setup Rare-Feature, or a stall step by mutator.
  - It reads Alfred's `sync:llm` imports and upstream's in-place seeds, so it also gives the final study's Table 13.
  - On 04's gpt-oss-20b campaigns it reproduces the 2026-11-08 analysis exactly.
- **Two accounts:** `STUDY_EXTRA_ACCOUNT`, `STUDY_EXTRA_MAX` and `STUDY_MAIN_MAX` for `scripts/study start`, ported
  from the private driver 04/05 used.
  - Quantumcore first; the class priority account takes the overflow.
  - Its G2FUZZ campaigns get the server's address.
- **Tests:**
  - `g2fuzz/tests/test_mutators.py`: the mutator sets, the setup rounds, and the `rare` mutator end to end against a
    fake LLM server. Run it in the image, which has openai.
  - `test_llm_worker.py`: the recorded mutator.
  - `scripts/tests/test_fuzz_cli.sh`: 27 new contracts for `--set`/`set:` and the extra account.


## The web stall mutator (2026-11-11)
`G2F_STALL_MUTATORS=web` (alone, or with others). A stall step that targets a feature no generator has yet, like
`rare`, but takes the feature from documents found on the web at that stall, not from the model's memory. The aim is
fresh, rare features as a long campaign goes on, which a one-time scrape can't give: it runs dry, and the model then
invents near-copies of features it already has.

**One step** (`generator_mutation.py` `mutation_web`, research in `g2fuzz/py_utils/web_step.py`):
1. **Pick a parent** generator (the scheduler) and its format.
2. **Write queries.** The LLM writes new search queries from:
   - the features already covered (the setup's `feature_pool-<format>.json` plus web features with a generator);
   - the queries already tried;
   - a search angle, the least used of eight (optional parts of the spec, extensions, deprecated features, CVEs and
     crafted files, parser bugs, encodings and metadata, versions, library edge cases).
3. **Search.** Each step uses the two least-used sources that aren't rate-limited. All of them are free and need
   no key (`py_utils/web_search.py`, `G2F_WEB_SOURCES`):
   - Wikipedia (article text);
   - NVD's CVE API (descriptions);
   - Stack Overflow;
   - GitHub issues;
   - links: up to two pages linked from documents read earlier, only where robots.txt allows.
4. **Read only new documents.** Every document read is remembered, so no later step reads it again, and its links
   join the reading list.
5. **Find features.** The LLM gets an excerpt of each new document: the paragraphs with the most format detail and
   the fewest covered features, at most 12,000 characters in all. It names uncovered features, each with a sentence
   quoted from its document and the part of the file that holds it (chunk, box, tag, marker, segment, field).
6. **Check them.**
   - **Grounded:** a feature is dropped unless its quote is really in the excerpt.
   - **New:** it is dropped if it matches a known feature, first by word overlap, then by asking the LLM. The
     document is then linked to the feature it matched, so covered features collect their documents too.
   - **Relevant** (added 2026-11-12): it must be a part of the format's own files. It is dropped if it names no part
     of the file, if it is like a feature turned down before, or if the same LLM check (no extra call) answers
     `off-format`: a related or successor format's feature (one with its own file type or codec) or a general
     algorithm. A part of another standard that the format's files carry still counts. Why: the first real web
     campaign (jhead, 13 steps) targeted JPEG 2000, JPEG XT and JPEG XS features and generic Huffman-coding ideas.
     Turned-down names stay in the ledger and are listed in later steps' prompts.
7. **Make the generator.** As `rare` does, the parent generator is extended with one new feature. The prompt carries:
   - the feature's description and the part of the file that holds it;
   - the quoted sentences and the part of the document around them;
   - the image's installed Python packages.
   If this stall found nothing new, a feature found earlier and not yet targeted is used (each gets 2 tries).

**The campaign's memory:**
- **`<target>_output/default/web_ledger.json`** (`py_utils/web_ledger.py`):
  - every feature, with its documents (url and quote) and its state: candidate, targeted with its generator,
    failed, covered by seed generation;
  - the rejected features and why;
  - every document, with its source, query and step, and the features it gave;
  - the reading list of links;
  - every query, with its new documents;
  - per-source cooldowns.
- **`web_docs/`** holds the excerpts the LLM read.
- **Campaigns never share** a ledger, so repetitions stay independent. `scripts/fuzz reuse` copies the setup's
  feature lists, never a ledger.
- **Not repeatable exactly:** the web changes, and the ledger is the record of what each campaign saw.
- **One limiter for all of Tempest** (`py_utils/web_limit.py`, added 2026-11-13): Tempest reaches the internet through
  one address and the free APIs count per address, so campaigns that each kept to a limit would together exceed it
  many times over (A01's `web` arm: about 9,000 requests an hour) and throttle every other Tempest user of those
  APIs. Every request takes a turn from one group folder (`<repo>/.web-limits`, bound into each campaign by
  `scripts/fuzz`): GitHub and NVD a turn per 7 s, Stack Exchange per 300 s (300 a day), Wikipedia per 1 s, any other
  site per 2 s, all across Tempest. A rate-limit answer makes every campaign back off; a turn more than 30 s away is
  skipped (the source cools down in that campaign; a skipped link goes back on the reading list). Turns are taken
  under a `mkdir` lock (atomic on NFS, and it can't hang if the file server stalls); a dead process's lock is taken
  over after 30 s. This is the only link between campaigns.

**Safety:** web text reaches prompts whose answers run as Python, so a page could carry instructions. Three layers:
- **Prompts:** web text is marked as reference data, not instructions, in every prompt.
- **The sandbox** (`py_utils/sandbox.py`): a web-informed generator runs only there, or not at all.
  - `unshare` gives it new user, network and mount namespaces: only loopback, and fresh `/tmp` and `/dev/shm`.
  - It can't reach the internet, the node's shared `/tmp` and `/dev/shm` (other jobs' files), or the worker and
    afl-fuzz.
  - `pip install` is off for it, so a page can't get a package installed.
  - Checked on Tempest compute nodes (Apptainer 1.5.4) on 2026-11-11.
- **Every campaign container** (all arms, `scripts/fuzz`) has:
  - `--no-mount home,cwd,tmp`, so it never sees your home folder (ssh keys, other repos) or the folder the job
    started in;
  - its own `/tmp` (`${TMPDIR:-/tmp}/alfred-tmp-<job>`, removed at the end), instead of the node's.
  - Before this, a generator could write anywhere in your home folder, and campaigns on one node shared `/tmp`.
    For example, 04's mp3gain generators download ffmpeg into it, so a later campaign could find it there.
- **`G2F_SANDBOX_ALL=1`** sandboxes every generator. It's a setup-time switch to test as a round. In 04, 3.7% of
  gpt-oss-20b's generators used the network, 40% on mp3gain (ffmpeg downloads).

**What `scripts/compare` and `scripts/lineage` add:**
- `compare`'s web table, per arm:
  - steps and queries (failed);
  - documents read and features found;
  - generators made and failed;
  - rejects (ungrounded, duplicate, off-format) and links queued;
  - queries and new documents per source.
- `lineage`'s `run-web` class.
- The worker's `steps.jsonl` records each rare or web step's feature and search numbers.

**`scripts/web-check [FORMAT ...]`** runs two web steps with fixed queries and no LLM, and prints what each source
returned. Run it on the nodes a round uses before launching one. On 2026-11-11, from the Mac and from a compute node
inside the image, all four sources answered: 14 documents for png and for tiff, and pages from the reading list in
step 2.

**Tests:**
- **`g2fuzz/tests/test_web.py`** (21 tests): a fake web (Wikipedia, NVD, Stack Exchange, GitHub, a spec site with
  robots.txt) and a fake LLM. It covers:
  - the ledger, the parsers and robots.txt;
  - rate limits, grounding, duplicates and excerpts;
  - two stalls in a row (new documents, no repeats);
  - the sandbox (no network; private `/tmp`);
  - the mutator end to end (its generator's seed records no network), and a step that refuses to run without the
    sandbox.
  - All pass in the image on a Tempest compute node. Plain Docker on the Mac can't start the sandbox, so its tests
    are skipped there.
- **`scripts/tests/test_fuzz_cli.sh`:** contracts for the new switches, the container mounts and private `/tmp`,
  and `reuse` copying the feature lists.
