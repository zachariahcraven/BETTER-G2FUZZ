# Setup checks (not results)

The checks that decided how to run the study (2026-10-22 and 23). Their campaigns are kept for the record in each
folder's `campaigns/` (git-ignored, moved here from the repos' `eval/` on 2026-10-23); their `job.sbatch`/`run.sh`
still show the paths they ran from.

| Check | Question | Answer |
| --- | --- | --- |
| [Model bake-off](#model-bake-off-2026-10-23) | Which local LLM for the G2FUZZ arms? | `Qwen3.8-27B-FP8-nothink`: the only one to finish seed generation in every run |
| [Pilot](#pilot-2026-10-23) | Do all 4 arms work end to end on the paper's targets? | Yes, after 3 fixes |
| [Smoke tests](#smoke-tests-2026-10-22) | Do the image and the AFL++ 5.03c port of G2FUZZ work with a local LLM? | Yes, with a non-thinking model |

## Model bake-off (2026-10-23)
The paper used GPT-3.5/GPT-4. 3 models x 3 targets (jhead, mp42aac, pdftotext) x 2 reps: seed generation, then 300 s
of fuzzing (WORKING-BETTERG2FUZZ, AFL++ 4.32c, paper-version targets). Servers: gpt-oss:120b (Ollama, the team server
of the time, 2 A40s), llama3:70b-instruct-q4_K_M (Ollama, 2 A40s,
[llm-serve-llama3.sbatch](model-bakeoff/llm-serve-llama3.sbatch)), Qwen3.8-27B-FP8-nothink (vLLM, 1 A100).

| | gpt-oss:120b | llama3:70b | Qwen3.8-nothink |
| --- | --- | --- | --- |
| Edges of the generated seeds alone, mean of 2: jhead / mp42aac / pdftotext | **248 / 1010 / 2830** | 138 / 337 / 2301 | 157 / 687 / 2705 |
| LLM calls over 290 s | 9 (8 in one run) | **1** | 3 |
| Seed generation finished within 2 h 35 min | 2 of 6 | 4 of 6 | **6 of 6** |
| Edges after 300 s of fuzzing: mp42aac / pdftotext | never fuzzed | 850, 846 / 4446 | **1170, 1034 / 4260, 4718** |

Qwen won: the only model to finish seed generation in all 6 runs (20–40 min each), and the most coverage after
fuzzing on mp42aac and pdftotext; gpt-oss's seeds reached the most edges, but it finished seed generation in only 2
of 6 runs. Every row: [bakeoff.tsv](model-bakeoff/bakeoff.tsv) (per campaign: calls, errors, latency, generators,
seeds, edges). Made by [launch.sh](model-bakeoff/launch.sh) (log: `launch.log`), analysed by
[analyze.sbatch](model-bakeoff/analyze.sbatch).

## Pilot (2026-10-23)
All 4 arms, 900 s of fuzzing each on jhead, libpng (`libpng_libpng_read_fuzzer`, FuzzBench) and mp42aac (UNIFUZZ,
extra arguments), in both repos. AFL arms by hand (`scripts/fuzz run pilotA-afl<432|503>-<target> 900 --afl`),
G2FUZZ arms with `--test` by [launch-g2.sh](pilot/launch-g2.sh). It found 3 problems, fixed in both repos that day:
1. 8 GB per campaign instead of 4 GB: g2432 libpng ran out of memory (LLM-written PNG seeds of ~10 MB).
2. `scripts/fuzz` copies only the files in `gen_seeds/` as seeds: g2503 mp42aac failed because a generator wrote a
   folder of frames, which stopped `cp`.
3. G2FUZZ-upgradedAFL had no `g2fuzz.sif.version`, so its campaigns recorded no image version.

Also decided: phase B uses only the A100 server, so LLM speed is the same for every campaign (calls on an A40 were
~2.5x slower). Campaigns: `pilot/campaigns/pilotA-<arm>-<target>[-b]/`.

## Smoke tests (2026-10-22)
| Campaign | Repo | What happened |
| --- | --- | --- |
| `smoke-1022` | WORKING-BETTERG2FUZZ | 300 s on jhead with no LLM calls (a finished campaign's seeds reused): 569 edges, 2 crashes. The image works. |
| `smoke503-jhead` | G2FUZZ-upgradedAFL | First try: compute nodes can't reach CatChat; then a thinking model's calls all hit G2FUZZ's 300 s limit. Stopped. |
| `smoke503b-jhead` | G2FUZZ-upgradedAFL | Qwen3.8 with thinking off: 21 generators, 30 seeds, 29 LLM calls, 0 timeouts; 912 s, 1.31M execs, 466 edges; 3 LLM steps imported 36 seeds. Passed. |

The 5.03c log shows `Coverage target: jhead.afl (CmpLog: jhead.cmp)`: AFL++ 4.32c's bug of fuzzing with the CmpLog
binary is gone in 5.03c (DRIFT.md 4.1). Campaigns: `smoke/campaigns/`.
