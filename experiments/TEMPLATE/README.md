# NN-short-name

**Question:** one sentence.
**Owner:** NetID(s). **Status:** planned / running / done. **Started:** YYYY-MM-DD.

## Design
What is compared (arms), on which targets, how long, how many repetitions, which model/server and image.
What it is compared against (e.g. `01-baseline-replication` campaigns, by path).

## Layout
| Folder | Holds |
| --- | --- |
| `launch/` | The exact commands that made every campaign (rerun from here) |
| `analysis/` | Scripts that turn `campaigns/` into `results/` |
| `results/` | Tables and figures for the report |
| `campaigns/` | Campaign data (git-ignored); names `<phase>-<target>-<arm>-r<rep>` |
| `setup/` | Optional: checks that decided how to run the study (not results) |

## Results
Filled in when the study ends: the answer to the question, with links into `results/`.
