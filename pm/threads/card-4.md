# card-4: Commit and push the Mac clone (A01 redesign, web limiter, docs)

## Note nom-nom 2026-11-13 17:15
The user commits (the auto-mode classifier blocks Claude's git commit). Reported as tested: CLI suite passes; test_web 28 OK in the image.

Uncommitted on branch `alfred` in `~/Desktop/Fall2026/Cyber/alfred`:
- A01 redesign: `experiments/A01-mutators-warm-2h` (renamed from A01-stall-mutators-6h): warm start from A00 control queues (`seeds = warm:`, `scripts/fuzz reuse --queue`), arms control/rare/web/no-pattern + afl-only, 2 h, 375 campaigns.
- Shared web limiter `g2fuzz/py_utils/web_limit.py` (staged) + `web_search.py`, `web_step.py`, `tests/test_web.py`.
- `scripts/study`, `scripts/fuzz`, `scripts/tests/test_fuzz_cli.sh`, `scripts/web-check`.
- Docs: `ALFRED-ROUNDS.md` (incl. A03 "scouts" proposal), `ALFRED.md`, `KNOWN_BUGS.md` (G2F-1/G2F-3 verified gone, OURS-5/6 added), experiments READMEs, `.gitignore`.
- Untracked: `.mr-klanky/`, `pm/`.

Timing: push before the deploy window (card-5). Do not pull on Tempest while A00/A02 run from the 01db4f3 image.
