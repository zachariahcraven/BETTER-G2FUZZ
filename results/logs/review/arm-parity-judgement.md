# Arm-parity judgement (results/tables/arm-parity.csv, 2026-10-16 13:36)

`experiments/analysis/arm-parity` compares each comparison's arms (and the reps within an arm) on the recorded
configuration: image, afl-fuzz command, seed source, binds, env, model/server, format description, oracle ranking and
seed content. Differences that are the experiment's own factor are `allowed`. Every other difference is `UNEXPECTED` and
is judged here.

**No UNEXPECTED rows** in: bandit-jhead, bandit-tiff, bandit-wad, bandit-xml, demo, wad, wad4h, wad4ht, wadp, xml, xml4h.

**UNEXPECTED rows** occur only in `lineup` (jhead, 82 rows), `png` (33) and `tiff` (33). All of them come from one cause:
those experiments mix campaigns from three periods. The jhead model arms r1-r3 ran 2026-10-09/10; the jhead/tiff/png
baselines and models r1-r3 ran 2026-10-13/14; the top-ups r4-r5 ran 2026-10-15/16 after the workspace reorganization.
The fields involved:

| field | what differs | evidence that it does not change behaviour |
|---|---|---|
| image | `7adcd8f built 10-09`, `7adcd8f-dirty built 10-13`, `7adcd8f-dirty reorg built 10-15` | afl-fuzz is byte-identical (sha256 1734e8eb...) in all three images (and in the 10-03 and 10-16 images). jhead.afl/jhead.cmp are byte-identical between the 10-09 and 10-13 images. The 10-13 -> 10-15 rebuild changed the binaries' bytes but not their behaviour: the reorganization regression check found identical coverage maps on every sampled input (tests/image/compare_targets.sh). |
| afl_cmd | `-k /AFLplusplus/` vs `-k /AFLplusplus/g2fuzz/` | Only the location of G2Fuzz's Python in the image layout (moved by the reorganization). |
| binds | individual files bound (generator_mutation.py, program_gen.py, py_utils, program_to_format.json) vs the whole `X/g2fuzz` folder vs none (10-09) | Same code path; the Python code itself is compared below. |
| stock_seeds | stock seeds pre-copied into initial_seeds (old) vs copied by run.sh (new) | The `seeds` field (hash of every seed file's content) is identical across all baseline reps, so the seed corpora are the same. |
| target | `missing` for the 10-09/10 jhead campaigns | Those campaigns predate target.txt; their binary is /targets/jhead.afl per their run.sh. |

Python code (G2Fuzz) of the 10-09 image vs today's X/g2fuzz: the scheduler hooks (random mode = the original
random.choice), format_text (identity without G2F_FORMAT_DESC_FILE) and the B1 failure record behave the same. One real
difference: the generated-seed size cap was 10 MB in the 10-09 code and 1 MB (G2F_MAX_SEED_KB=1024) from 10-13 on. Across
all jhead/tiff/png LLM campaigns r1-r3 this affects exactly one file: lineup-qwen4b-r2 kept gen_seeds/jpg-4_2.jpg
(1.16 MB), which the later code would have deleted. The tiff/png r1-r3 campaigns already used the 1 MB cap (their logs
say "greater than 1024 KB").

Not recorded by any campaign and therefore not checked by the tool: the node each run used and its load. The
execs-matched analysis (results/tables/stats-execs-matched.csv) exists because throughput did differ between arms (e.g.
the wadp follow-up controls ran 10 at once on one node and did about half the executions of the spec arm).

Verdict: the UNEXPECTED rows are configuration-recording differences between campaign periods with no behavioural
effect, except the single 1.16 MB jhead seed noted above.
