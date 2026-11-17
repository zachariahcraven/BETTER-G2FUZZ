# A06-uncovered-check-6h

Two additions to the `uncovered` mutator, against `uncovered` in continuous mode as A03 kept it. 15 targets, 6 h,
5 reps, gpt-oss-20b, new shared seeds: 300 campaigns and 15 seed generations.

**Where the ideas come from.** A literature search by another session (2026-11-17): PALM (arXiv 2506.19287) and
HyLLfuzz (arXiv 2412.15931) give the LLM the conditions of the blocked branch as a goal; SeedSmith (arXiv
2607.08949) and Cottontail (arXiv 2504.17542) check each LLM answer against the instrumented target and ask again.
None of them tested local open models or compared coverage with AFL++ on file-format targets, so this round is
the test.

**Arms.**

| Arm | Switches on top of continuous `uncovered` | What changes |
|---|---|---|
| `uncovered-cont` | none | control |
| `cond` | `G2F_UNCOVERED_CONDITIONS=1` | the prompt lists up to 8 conditions of the function that were only ever true, or only ever false |
| `check` | `G2F_UNCOVERED_CHECK=2` | the new generator's files (at most 16) are run through the source-coverage build; if no marked line is reached, the LLM is told whether the function was called at all and asked again, at most twice |
| `check-cond` | both | |

With the check on, a function whose marked lines were reached is not picked again in the campaign, and neither is
one that failed 3 checked steps. This matters on targets with short lists: in A03 a jhead campaign made 388 steps
over 13 functions, and the two largest (`ProcessFile`, `main`) have lines that only command-line options reach.

**Cost of a check** (measured on Tempest's login node, 16 files): jhead 0.3 s, pdftotext 2 s, freetype2 6.5 s,
bloaty 37 s (llvm-cov reads the coverage map of a 42 MB binary). A step takes about a minute, so on bloaty the
`check` arms make clearly fewer steps; the comparison includes that cost.

**Not tested.** Showing the LLM a queue file that enters the function (HyLLfuzz): the files are binary, and the
check's feedback already says whether the function was called.

**Reading it.** `scripts/compare A06-uncovered-check-6h --control uncovered-cont`. Keep rule as in
`docs/ALFRED-ROUNDS.md`. The step log has `entered`, `reached` and `asked` per checked step: the share of steps
that reach a marked line, first time and after feedback, says whether the check does anything.

**Needs** an image with these switches, and the lists made again
(`LISTS_ONLY=1 build/targets/build-uncovered.sh <any folder> <targets>`): old lists have no line numbers, and the
check then measures nothing.
