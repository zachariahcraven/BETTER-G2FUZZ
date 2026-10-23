# Setup checks (not results)

Checks that decided how to run the study. Their campaigns are kept for the record; only the decisions matter.

| Check | Question | Answer |
| --- | --- | --- |
| [model-bakeoff](model-bakeoff/) | Which local LLM for the G2FUZZ arms? | `Qwen3.8-27B-FP8-nothink`: the only one to finish seed generation in every run |
| [pilot](pilot/) | Do all 4 arms work end to end on the paper's targets? | Yes, after 3 fixes: 8 GB per campaign, seed folders skipped, image version recorded |
| [smoke](smoke/) | Do the image and the AFL++ 5.03c port of G2FUZZ work with a local LLM? | Yes, with a non-thinking model (G2FUZZ times out LLM calls after 300 s) |

Campaign data: `campaigns/` in each check (git-ignored), moved here from the repos' `eval/` on 2026-10-23. Their
`job.sbatch`/`run.sh` still show the paths they ran from.
