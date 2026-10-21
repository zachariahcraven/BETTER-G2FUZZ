# Review record: arm-parity

- Files: experiments/analysis/arm-parity
- Spec: tasks/arm-parity.md
- Author: gemma-4-31B-it (N-version: qwen38 + Claude reference)
- Status (computed from the passes below): PASSED (driver rule: clean streak 4 since the last fix, families gemma, qwen, non-author yes)
- Manager's note: PASSED: 4 consecutive clean passes (qwen38 x3 non-author, gemma) after fix round 1. Real data: byte-identical to Claude's reference. Earlier rounds (before review): Claude found a piped check command that always exited 0 (runs restarted), os.walk performance (fix round), spec amended twice before use (missing target.txt; format_desc allowed when LLM use differs). qwen38's independent version had 2 bugs (binds not filtered by destination; /g2f-seeds counted as stock) - not deployed.

## Events (in order)

- Pass 1: qwen38, checklist 1-spec -> **findings** (2026-10-16 10:24:40)
  - F1 [medium] experiments/analysis/arm-parity:156: When initial_seeds/ exists but contains no regular files (empty or only subdirectories), the code hashes the string '\n' instead of the empty string, producing an incorrect 12-hex-digit seed fingerprint.
- Pass 2: qwen38, checklist 3-data-io -> **findings** (2026-10-16 10:22:29)
  - F1 [high] experiments/analysis/arm-parity:55: The afl_cmd regex r'afl-fuzz .*? @@' uses '.' which does not match newline characters. If the afl-fuzz command in run.sh spans multiple lines (e.g., via shell backslash line continuations), the regex fails to match and the field silently becomes 'missing', producing false UNEXPECTED differences between campaigns that are functionally identical.
- Pass 3: qwen38, checklist 7-parity -> **clean** (2026-10-16 10:19:29)
- Judgement (pass 1, F1): **valid**: empty initial_seeds hashed '\n' instead of '' (spec deviation; no effect on real data). Test added, validated on reference.
- Judgement (pass 2, F1): **valid**: afl_cmd regex did not span newlines (spec says up to the next ' @@'; all real run.sh are one line). Test added.
- Fix round 1: butler run 20261016-102523-95955 (re.DOTALL; ''.join of lines)
- Pass 4: qwen38, checklist 1-spec -> **clean** (2026-10-16 10:35:01)
- Pass 5: qwen38, checklist 3-data-io -> **clean** (2026-10-16 10:31:42)
- Pass 6: qwen38, checklist 5-errors -> **clean** (2026-10-16 10:28:54)
- Pass 7: gemma, checklist 5-errors -> **clean** (2026-10-16 10:27:19)
