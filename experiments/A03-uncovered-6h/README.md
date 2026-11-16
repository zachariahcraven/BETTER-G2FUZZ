# A03-uncovered-6h

**Question:** does the `uncovered` stall mutator (coverage feedback for the LLM) still add coverage with a new seed
set and from a cold start, over Alfred's control and plain AFL++?
**Owner:** n59m742. **Status:** launched 2026-11-15. **Started:** 2026-11-15

## Design
- Round A03 of [docs/ALFRED-ROUNDS.md](../../docs/ALFRED-ROUNDS.md): the repeat its acceptance rule asks for after
  A01, where `uncovered` beat `afl-only` on 11 of 15 targets (median ratio 1.013, Wilcoxon p = 0.003; pdftotext and
  sndfile significant, none significantly worse) and upstream's mutators did not (p = 0.517).
- **Arms** (`launch/study.conf`), 15 targets x 5 reps x 6 h, shared seeds generated for this round:
  - `control`: Alfred's defaults (feature, structure, pattern after a 300 s stall).
  - `afl`: AFL++ 5.03c with CmpLog from the stock seeds. Baseline, no decision.
  - `uncovered`: stall mode as control; every step is the `uncovered` mutator.
  - `uncovered-cont`: `uncovered` in continuous mode (A01's setting).
- **Decision:** `uncovered` (either mode) is kept if it passes the keep rule against `control`: Wilcoxon p < 0.05
  over the 15 targets, no target significantly worse. Then it becomes Alfred's default for the check round and the
  final study. If neither mode passes, A01's gain was a warm-start effect and the write-up says so.
- **Known limits:**
  - The uncovered lists come from A00 control's queues after 6 h (other seeds, the earlier target builds of the
    same sources). Early in a cold run AFL++ reaches some listed lines by itself, so early steps can be wasted.
  - Some listed lines sit behind command-line options the fuzz run never passes.
  - A01: 7 of 75 `uncovered` campaigns had one out-of-memory kill of a child process (control and afl-only: none);
    every campaign ran its full time. Watch for it here.
