# Practice

Everyday and test runs: trying the setup, checking a code change, a quick run on a new target. Nothing here is a
result; a run that answers a question belongs in a study (see [../README.md](../README.md)).

`scripts/fuzz` puts campaigns in `practice/campaigns/` unless `G2F_EVAL` says otherwise, so nothing needs setting:

```bash
scripts/fuzz reuse example $USER-try       # example's seeds + generators: skips seed generation
scripts/fuzz run $USER-try 2400 --test      # ~40 min, with 2-3 LLM steps (each ~13 min on an A40)
```

Put your NetID in each name (the folder is shared). Old runs may be moved out at any time. Runs use the UCB generator
scheduler unless you add `--scheduler random` (upstream's); `scripts/fuzz status <name>` shows which.

| Campaign | What it is |
| --- | --- |
| `example` | The quick-start run: jhead, 34 seeds and 32 generators (image bdb816a). Keep it: `reuse example` needs it |
| `t19z813-ucb-smoke` | Wyatt's UCB test (2026-10-24). It ran the **random** scheduler: image bdb816a didn't contain UCB yet (66033fa does) |
