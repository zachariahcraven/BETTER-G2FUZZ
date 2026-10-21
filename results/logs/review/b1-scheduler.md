# Review record: b1-scheduler

- Files: g2fuzz/py_utils/scheduler.py, g2fuzz/generator_mutation.py:137-340, afl/src/afl-fuzz.c:546-640, afl/src/afl-fuzz.c:3385-3440
- Spec: tasks/b1-scheduler.md
- Author: legacy
- Status (computed from the passes below): PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes)

## Events (in order)

- Pass 1: qwen38, checklist 1-spec -> **findings** (2026-10-15 18:00:11)
  - F1 [high] g2fuzz/generator_mutation.py:232: If gen_code_debug or self_debug raises an exception (e.g. LLM API error), record_mutation is never called, violating the spec's requirement that 'EVERY step that picked a mutator must end with exactly one record_mutation call, including steps that end in an exception.' The same defect exists in mutation_based_on_pattern (line 173) and in the __main__ block which has no top-level try/except either.
- Judgement (pass 1, F1): **valid**: Confirmed in logs: 30 bandit-round steps died on openai 400 context overflow before record_mutation; failures never reach the mutator arm. Needs a fix round (record failure on exception).
- Fix round 1: butler qwen38 run 20261015-180939: run_step() records a failure (record_mutation(out, mutator, None)) on any exception and re-raises; __main__ dispatches through it. Judge test tests/test_b1_fix.py (validated on reference) passes. Note: BaseException also records a step killed at campaign end.
- Pass 2: gemma, checklist 5-errors -> **findings** (2026-10-15 18:17:10)
  - F1 [medium] afl/src/afl-fuzz.c:560: Subprocess failure from generator_mutation.py is ignored, treating the step as a success (or at least not a failure) and proceeding to attempt queue ingestion.
- Judgement (pass 2, F1): **reject**: By design: the fuzzer continues after a failed LLM step; the failure is printed ('Command failed') and, after fix round 1, recorded by run_step. gen_seeds is only filled on the success path (mv_files), so nothing from a failed step is ingested.
- Pass 3: qwen38, checklist 2-edges -> **findings** (2026-10-15 18:27:35)
  - F1 [high] afl/src/afl-fuzz.c:581: The file counter `cnt` is declared as `u8` (unsigned 8-bit, max 255) in run_gen_seeds. If gen_seeds contains more than 255 files, cnt wraps modulo 256, so the returned count is wrong and the caller's target_seeds loop processes the wrong number of newly-queued entries.
- Pass 4: gemma, checklist 7-parity -> **clean** (2026-10-15 18:28:23)
