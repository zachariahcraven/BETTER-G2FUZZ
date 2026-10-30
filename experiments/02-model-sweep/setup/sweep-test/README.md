# Sweep test (2026-10-29)

Checks that `launch/sweep` works end to end before the real runs. Not results.

Command: `MAX_SEEDGEN=2 launch/sweep start Qwen3.8-27B-FP8 600 0` (rep 0 = test), image 66033fa, Qwen3.8 on one A40.

| Campaign | Seed generation | Fuzzing | Result |
| --- | --- | --- | --- |
| `jhead-r0` | 22 min | 600 s | done: 498 edges, 18 crashes, 16 generators, 23 LLM calls |
| `gdk-pixbuf-pixdata-r0` | 115 min | 600 s | done: 1367 edges, 26 crashes, 81 generators, 110 LLM calls |

Checked: the seed-generation limit (2 launched, 13 held back), a second `start` launched nothing again, `launch.txt`,
`status` and `csv`. What it changed: the 115 min seed generation led to `G2F_SEEDGEN_MIN=300` in `sweep` (the default
120 min job budget was nearly used up) and the `done (short)` state. Data: `campaigns/Qwen3.8-27B-FP8/` (git-ignored).
