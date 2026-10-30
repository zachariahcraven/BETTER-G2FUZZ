# Example Run: G2Fuzz with a Local Model on Tempest

A real run from 2026-10-21: target jhead, model `gpt-oss:120b`, 900 s with `--test`, in the shared copy.
Everything below is the actual output (`llm status` now also names the server's owner). About 30 minutes end to end.
Since 2026-10-23 the team server is Qwen3.8 on one A40 (README.md, Tempest setup step 8): the commands are the same,
`new` says `model Qwen3.8-27B-FP8-nothink`, and a ready server shows `ready: Qwen3.8-27B-FP8-nothink on <node>`.
Since 2026-10-29: campaigns go in `experiments/practice/campaigns/` (this run's folder was `eval/example`), `run` also
prints the generator scheduler (`ucb` by default; `--scheduler random` for upstream's), there is one server per model
(`--model`), and seed generation takes 20 min to 2 h depending on the target.

Before you start: [Tempest setup](../README.md#tempest-setup) steps 1–6 are done. Campaign folders are shared, so
use your own name: the commands below say `$USER-example`; the output shows this run's name, `example` (that folder
still exists).

**Faster (~40 min):** reuse this run's seeds and generators, skipping seed generation (step 2's 11–20 min):
`scripts/fuzz reuse example $USER-try && scripts/fuzz run $USER-try 2400 --test` (each LLM step takes ~13 min on an A40).

```bash
cd /home/group/csci-591-automated-vulnerability-discovery/students/BETTERG2FUZZ
```

## 1. Check the team's model server

One server per model, shared by everyone's runs of that model. `scripts/fuzz llm status` says whether one is up. Start one
only if there's none ([step 8](../README.md#tempest-setup)). Two ways, same model:

| | Command | GPU | Start |
| --- | --- | --- | --- |
| **Fast, assured** | `scripts/fuzz llm start 3` | 1× A40, `gpupriority`, class priority account | right away |
| **Queued** | `scripts/fuzz llm start 3 h100` | 1× H100, `gpufairshare` | can wait hours or days |

This run used the gpt-oss server of the time, on 2 A40s (`llm start 3 a40` then; now plain `llm start 3`):

```console
$ scripts/fuzz llm start 3 a40
submitted server job 851143 (a40, 3 h, account priority-csci-591-automated-vulnerability-discovery). Ready ~4 min after it starts: scripts/fuzz llm status
$ scripts/fuzz llm status
     JOBID     STATE        TIME   TIME_LEFT NODELIST
    851143   RUNNING        0:31     2:59:29 gpu049
loading the model (~4 min)
$ scripts/fuzz llm status          # 3 minutes later
     JOBID     STATE        TIME   TIME_LEFT NODELIST
    851143   RUNNING        3:37     2:56:23 gpu049
ready: llm-serve: gpt-oss:120b loaded on gpu049 at Wed Oct 21 03:21:38 PM MDT 2026
```

## 2. Create and run a campaign

```console
$ scripts/fuzz new $USER-example
created experiments/practice/campaigns/example (target jhead, model gpt-oss:120b)
next: scripts/fuzz run example [secs]
$ scripts/fuzz run $USER-example 900 --test
TEST MODE: llmGen-M after 10 s without new coverage (not for experiments)
no seeds yet: seed generation first (~15-20 min), then fuzzing
submitted Slurm job 851172 (fuzz 900s, limit 165 min, account group-csci-591-automated-vulnerability-discovery). Watch it: scripts/fuzz watch example
```

`--test` makes the LLM step fire after 10 s without new coverage, so a short run shows one. Drop it for experiments.

## 3. Watch it

`scripts/fuzz watch $USER-example` updates every second (Ctrl-C leaves it running). One snapshot during fuzzing:

```console
$ scripts/fuzz status $USER-example
example  [running]

phase        fuzzing
run time     0:06:59
corpus       779
crashes      6
coverage     602 edges (30.68%)
speed        2489.10 execs/s, 874349 total
last find    30s ago   (LLM step after 10s without one)
llmGen-M     1 steps
LLM calls    52 (52 ok)   last: ok after 34.69s, 344s ago
```

The whole run:

| Time | Phase | Corpus | Coverage | LLM calls |
| --- | --- | --- | --- | --- |
| 15:22 | seed generation starts | 0 | – | 0 |
| 15:28 | seed generation | 0 | – | 29 |
| 15:34 | fuzzing (seeds loaded) | 240 | – | 51 |
| 15:36 | fuzzing | 465 | 522 edges | 52 |
| 15:40 | fuzzing | 779 | 602 edges | 52 |
| 15:49 | finished | 1062 | 615 edges | 61 |

Seed generation took about 11 minutes. Then 15 minutes of fuzzing, with 2 LLM steps.

## 4. Results

```console
$ scripts/fuzz results $USER-example
== example
run_time          : 900
execs_done        : 1552543
execs_per_sec     : 1725.04
corpus_count      : 1062
stability         : 100.00%
saved_crashes     : 14
edges_found       : 615
total_edges       : 1962
generators        : 32
llmGen-M steps    : 2
LLM calls         : 61 (61 ok, 0 errors)
generator lineage : {"xmp-5.py": ["xmp-31.py"], "jpg-9.py": ["jpg-32.py"]}
crashes dir       : experiments/practice/campaigns/example/jhead_output/default/crashes
```

## 5. What the run left in `experiments/practice/campaigns/example/`

| Path | What it is |
| --- | --- |
| `initial_seeds/` | 34 seeds: 1 stock JPEG + 18 `jpg-*` and 15 `xmp-*` from LLM-written generators |
| `jhead_output/default/generators/` | 32 generators: `jpg-1..15`, `xmp-1..15` from seed generation; `jpg-32`, `xmp-31` from the 2 LLM steps |
| `jhead_output/default/crashes/` | 14 crashing inputs (`sig:11` = segfault) |
| `jhead_output/default/queue/` | the 1062-input corpus |
| `llm_calls.jsonl` | one line per LLM call: 61, all `ok`, no retries |
| `seedgen.log`, `fuzz.log`, `slurm-851172.out` | logs |
| `image-version.txt` | the image the run used |

## 6. Stop the server (its owner, when the experiment is done)

```bash
scripts/fuzz llm stop
```

It refuses while anyone's campaigns still run. The GPUs otherwise stay booked until the server's time limit.
