# card-9: Fonts hint switch for freetype2 seed generation (gpt-oss invents fontTools APIs)

## Note nom-nom 2026-11-13 17:46
Files: g2fuzz/py_utils/font_hint.py, g2fuzz/py_utils/func.py, g2fuzz/generator_mutation.py, g2fuzz/tests/test_mutators.py, docs/ALFRED.md, docs/ALFRED-ROUNDS.md, scripts/fuzz, scripts/tests/test_fuzz_cli.sh

## Note nom-nom 2026-11-13 17:46
**Evidence** (read-only from Tempest, A00 seed generation, gpt-oss-20b, fontTools 4.65.0 pip-installed by the model; gathered by a sub-agent, numbers from each target's `seeds/gpt-oss-20b-<target>/seedgen.log`):

| Target | Generators run | Kept | Seed-gen time |
|---|---|---|---|
| freetype2_ftfuzzer | 163 | 40 (25%) | 5.5 h |
| woff2_convert_woff2ttf_fuzzer | 57 | 16 (28%) | 2.6 h |
| jhead | 28 | 23 (82%) | 19 min |
| libpng_read_fuzzer | 17 | 14 (82%) | 25 min |

- All 122 freetype2 generators that used fontTools failed; 213 of 254 failed runs name fontTools objects that don't exist (`cmap.newSubtable`, `CmapSubtableFormat4`, `TTFont.newTable`, ...). The 40 kept ones avoid fontTools and hand-pack tiny tables with `struct` (seeds mostly 64-490 bytes).
- In the continuous arm, freetype2's in-run LLM steps produced seeds 32 of 217 times (15%), against 74% on jhead and 88% on libpng; those failures are `struct.error` in mutations of the struct-only parents.

**Change:** `G2F_FONT_HINT=1` (setup switch, default off). For ttf/otf/woff/woff2 it appends a working `FontBuilder` skeleton and a list of the invented names to the generator-writing prompts (seed generation and the in-run feature/structure/pattern/rare/web mutators). Not covered: the `self_debug` repair prompts.

**Tested:** off or `0`, the `func.py` prompts hash identical to HEAD; the skeleton runs under fontTools 4.65.0 and writes ttf/woff/woff2 that read back; `test_mutators.py` 18 OK, `test_llm_worker.py` 9 OK, `test_web.py` 28 OK (3 skipped, no `unshare` on macOS); `scripts/tests/test_fuzz_cli.sh` run on Tempest in a scratch copy: "tweaks lists the switches" ok.

**Not tested:** against the model (server down). Whether it helps is unknown.

**Risks:** the hint tells the model not to hand-pack with `struct`, which is the only approach that works today. Only ttf and woff2 have evidence; otf/woff are by analogy. As a setup switch it needs `seeds = fresh`, so an arm repeats seed generation.

**Suggested first step once the server is back:** one freetype2 seed generation with `--set G2F_FONT_HINT=1`, then scan its `seedgen.log` the same way. A full arm on two targets cannot pass the 60%-of-targets keep rule; judge it by generators kept and seed-generation time. It overlaps with A03's library scout.

`scripts/fuzz` and `scripts/tests/test_fuzz_cli.sh` are shared with card-8.

## Note nom-nom 2026-11-13 17:46
Review:
##### To check
- Read the hint text in `g2fuzz/py_utils/font_hint.py`: is telling the model not to hand-pack with `struct` what you want?
- `python3 -m unittest g2fuzz/tests/test_mutators.py` from `g2fuzz/`: OK (some skipped without the openai package).
- The evidence table is in this card's notes: freetype2 kept 40 of 163 generators, all 122 fontTools ones failed.
##### Changed
New opt-in switch `G2F_FONT_HINT=1`: for font formats, generator prompts end with a working fontTools `FontBuilder` skeleton and the invented names to avoid. Default off, and off leaves every prompt unchanged. Not yet run against a model, so whether it helps is unknown.

## Note human 2026-11-13 17:57
Approved and committed (963fdb0).
