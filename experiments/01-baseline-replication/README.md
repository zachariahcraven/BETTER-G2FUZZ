# 01 Baseline replication

**Question:** does G2FUZZ beat AFL++(cmplog) on the paper's targets with our setup, as in the paper's Table 1?
We rerun the paper's evaluation before changing anything, so later studies have a baseline on our own setup.
**Status:** setup done (2026-10-23); phase B next. **Design and dated changes:** [PLAN.md](PLAN.md).
**Differences from the paper:** [DRIFT.md](DRIFT.md).

## Arms
| Arm | Repo | AFL++ | What runs |
| --- | --- | --- | --- |
| `g2432` | WORKING-BETTERG2FUZZ | 4.32c | G2FUZZ: LLM seed generation, then fuzzing with LLM mutation steps |
| `afl432` | WORKING-BETTERG2FUZZ | 4.32c | AFL++(cmplog), the paper's baseline: `scripts/fuzz run --afl`, stock seeds |
| `g2503` | G2FUZZ-upgradedAFL | 5.03c | G2FUZZ |
| `afl503` | G2FUZZ-upgradedAFL | 5.03c | AFL++(cmplog) |

Model for the G2FUZZ arms: `Qwen3.8-27B-FP8-nothink` (vLLM). Why: [setup/model-bakeoff](setup/model-bakeoff/).
Each arm runs with its own repo's scripts and image; all campaign data is kept here in one place.

## Phases
| Phase | What | Status |
| --- | --- | --- |
| Setup | Which model? Do all 4 arms work end to end? ([setup/](setup/)) | done |
| B | UNIFUZZ: 10 programs x 4 arms x 5 reps x 6 h = 200 campaigns | next |
| C | The paper's 24 h x 5 on UNIFUZZ, then MAGMA and FuzzBench | needs approval |

## Layout
| Folder | Holds |
| --- | --- |
| `launch/` | `phaseB.sh`: the exact commands behind every phase B campaign |
| `analysis/` | Coverage replay on one common binary, ASan bug triage, statistics |
| `results/` | Report tables and figures |
| `campaigns/` | Data, git-ignored. `B-<program>-<arm>-r<rep>`, e.g. `B-mp42aac-g2503-r3` |
| `setup/` | The checks that decided how to run the study (not results) |

Look at a campaign: `G2F_EVAL=$PWD/campaigns scripts/fuzz results B-mp42aac-g2503-r3` from the arm's repo
(`afl432`/`g2432`: WORKING-BETTERG2FUZZ, `afl503`/`g2503`: G2FUZZ-upgradedAFL).
