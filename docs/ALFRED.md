# Alfred: separate from BETTERG2FUZZ

Alfred started 2026-11-07 as a copy of BETTERG2FUZZ (`students/alfred`, git branch `alfred`). Both can run
studies at the same time without touching each other.

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
`paper/` and `latest/` were copied from `students/g2f-targets` on 2026-11-07 (AFL++ 4.32c, LLVM 16) and match this
code until the AFL++ upgrade, which rebuilds them. It has no builder images yet, so `build-paper.sh` stops until
Alfred's own builders exist.
