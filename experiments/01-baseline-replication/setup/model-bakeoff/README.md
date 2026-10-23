# Model bake-off (2026-10-23)

**Question:** which local LLM should the G2FUZZ arms use (the paper used GPT-3.5/GPT-4)?
**Answer:** `Qwen3.8-27B-FP8-nothink`. It was the only model to finish seed generation in all 6 runs (20–40 min each),
and it had the most coverage after fuzzing on mp42aac and pdftotext. gpt-oss's generated seeds reached the most edges,
but it finished seed generation in only 2 of 6 runs within the 2 h 35 min limit.

**Setup:** 3 models x 3 targets (jhead, mp42aac, pdftotext) x 2 reps; seed generation, then 300 s of fuzzing;
WORKING-BETTERG2FUZZ (AFL++ 4.32c), paper-version targets. Servers: gpt-oss:120b (Ollama, the team server of the
time, 2 A40s), llama3:70b-instruct-q4_K_M (Ollama, 2 A40s, [llm-serve-llama3.sbatch](llm-serve-llama3.sbatch)),
Qwen3.8-27B-FP8-nothink (vLLM, 1 A100).

| | gpt-oss:120b | llama3:70b | Qwen3.8-nothink |
| --- | --- | --- | --- |
| Edges of the generated seeds alone, mean of 2: jhead / mp42aac / pdftotext | **248 / 1010 / 2830** | 138 / 337 / 2301 | 157 / 687 / 2705 |
| LLM calls over 290 s | 9 (8 in one run) | **1** | 3 |
| Seed generation finished within 2 h 35 min | 2 of 6 | 4 of 6 | **6 of 6** |
| Edges after 300 s of fuzzing: mp42aac / pdftotext | never fuzzed | 850, 846 / 4446 | **1170, 1034 / 4260, 4718** |

Every row: [bakeoff.tsv](bakeoff.tsv) (per campaign: calls, errors, latency, generators, seeds, seed edges, edges
after 300 s). Made by [launch.sh](launch.sh) (log: launch.log), analysed by [analyze.sbatch](analyze.sbatch).
Campaigns: `campaigns/bake-<model>-<target>-r<rep>/` (git-ignored).
