# A05-check-3models-6h

The check round before the final study: Alfred with what the rounds kept (`uncovered` in continuous mode, the
generator limits) against Alfred as it was before the rounds, on three models and the paper's 28 targets, 6 h,
3 reps, with plain AFL++ beside them. 588 campaigns and 84 seed generations.

**Question.** A03 showed the gain with gpt-oss-20b on 15 targets. Does it hold (a) with phi-4 and Qwen3.8,
(b) on the 13 targets no round has run?

**Reading it.** Per model: `scripts/compare A05-check-3models-6h --control <model>-control`, and read the
`<model>-alfred` row. The final study runs `uncovered` in continuous mode if the gpt-oss-20b row passes the keep
rule on 28 targets and no model's row has a target that is significantly worse. A model whose row shows no gain
is reported as such; it does not stop the final study.

**Needs** an image with the generator limits (commit d492cca or later) and a `<target>.uncovered.json` for all 28
targets (A00's 15 from A01's setup, the other 13 from A04).
