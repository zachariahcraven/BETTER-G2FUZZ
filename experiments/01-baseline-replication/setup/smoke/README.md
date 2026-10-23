# Smoke tests (2026-10-22)

**Question:** do the reorganized image and the AFL++ 5.03c port of G2FUZZ run with a local LLM?
**Answer:** yes, with a non-thinking model.

| Campaign | Repo | What happened |
| --- | --- | --- |
| `smoke-1022` | WORKING-BETTERG2FUZZ | 300 s on jhead with no LLM calls (a finished campaign's seeds reused): 569 edges, 2 crashes. The image works. |
| `smoke503-jhead` | G2FUZZ-upgradedAFL | First try: compute nodes can't reach CatChat; then a thinking model's calls all hit G2FUZZ's 300 s limit. Stopped. |
| `smoke503b-jhead` | G2FUZZ-upgradedAFL | Qwen3.8 with thinking off: 21 generators, 30 seeds, 29 LLM calls, 0 timeouts; 912 s, 1.31M execs, 466 edges; 3 LLM steps imported 36 seeds. Passed. |

The 5.03c log shows `Coverage target: jhead.afl (CmpLog: jhead.cmp)`: AFL++ 4.32c's bug of fuzzing with the CmpLog
binary is gone in 5.03c (DRIFT.md 4.1). Campaigns: `campaigns/` (git-ignored).
