# Review records

Every reviewed task (one file each) and every other review pass. A pass is one fresh-context model review against
one checklist; findings were judged by Claude (valid -> fix round, rejected -> reason logged). Evidence folders are
on the manager's Mac (~/.claude/butler/runs, gauntlet).

| task | passes | status |
|---|---|---|
| a0-cov-replay | 5 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| a0-cov-summary | 4 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| a0-crash-triage | 5 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| a0-runners | 6 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| a0-scripts-fuzz | 3 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| a0-seedcov-fix | 3 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| a1-stats | 4 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| a5-spearman | 3 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| arm-parity | 7 | PASSED (driver rule: clean streak 4 since the last fix, families gemma, qwen, non-author yes) |
| b1-scheduler | 4 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| b2-budget | 4 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| b3-sim | 3 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| b4-oracle | 3 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| c1-controls | 3 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| d1-glue | 3 | PASSED (driver rule: clean streak 3 since the last fix, families gemma, qwen, non-author yes) |
| doom-demo | 5 | PASSED (driver rule: clean streak 5 since the last fix, families gemma, qwen, non-author yes) |
| doom-rootcauses | 14 | ESCALATE (driver rule: clean streak 5 since the last fix, families gemma, non-author yes) |
| execs-matched | 5 | PASSED (driver rule: clean streak 4 since the last fix, families gemma, qwen, non-author yes) |

## Other review passes (outside a gauntlet task file)

| run | model | checklist | verdict | findings |
|---|---|---|---|---|
| review-a5-gemma-4-31B-it | gemma-4-31B-it | 3-data-io | clean | 0 |
| review-a5-gemma-5 | gemma-4-31B-it | 5-errors | clean | 0 |
| review-a5-qwen38 | qwen38 | 3-data-io | clean | 0 |
| review-dfollow-gemma | gemma | 7-parity | clean | 0 |
| review-dfollow-qwen38 | qwen38 | 7-parity | clean | 0 |
| review-e3-gemma-3 | gemma | 3-data-io | failed | 0 |
| review-em-g-5 | gemma-4-31B-it | 5-errors | clean | 0 |
| review-em-q-1-spec | qwen38 | 1-spec | failed | 0 |
| review-em-q-1-spec-b | qwen38 | 1-spec | clean | 0 |
| review-em-q-3-data-io | qwen38 | 3-data-io | clean | 0 |
| review-em-q-6-stats | qwen38 | 6-stats | clean | 0 |
| review-lineupfix-gemma | gemma | 5-errors | findings | 1 |
| review-lineupfix-qwen38 | qwen38 | 5-errors | clean | 0 |
| review-parity-1-spec | qwen38 | 1-spec | findings | 1 |
| review-parity-3-data-io | qwen38 | 3-data-io | findings | 1 |
| review-parity-7-parity | qwen38 | 7-parity | clean | 0 |
| review-parity2-g-5 | gemma-4-31B-it | 5-errors | clean | 0 |
| review-parity2-q-1-spec | qwen38 | 1-spec | clean | 0 |
| review-parity2-q-3-data-io | qwen38 | 3-data-io | clean | 0 |
| review-parity2-q-5-errors | qwen38 | 5-errors | clean | 0 |
| review-prereg-b4-gemma | gemma | 7-parity | clean | 0 |
| review-prereg-b4-qwen38 | qwen38 | 7-parity | clean | 0 |
| review-prereg-gemma-7 | gemma | 7-parity | clean | 0 |
| review-prereg-qwen38-7 | qwen38 | 7-parity | clean | 0 |
| review-rc1-gemma-4-31B-it | gemma-4-31B-it | 9-rootcause | clean | 0 |
| review-rc1-gemma-postfix | gemma-4-31B-it | 9-rootcause | clean | 0 |
| review-rc1-qwen38 | qwen38 | 9-rootcause | findings | 1 |
| review-rc2-gemma-4-31B-it | gemma-4-31B-it | 9-rootcause | clean | 0 |
| review-rc2-gemma-postfix | gemma-4-31B-it | 9-rootcause | clean | 0 |
| review-rc2-qwen38 | qwen38 | 9-rootcause | findings | 1 |
| review-rc3-gemma-4-31B-it | gemma-4-31B-it | 9-rootcause | clean | 0 |
| review-rc3-qwen38 | qwen38 | 9-rootcause | clean | 0 |
| review-rc4-gemma-4-31B-it | gemma-4-31B-it | 9-rootcause | clean | 0 |
| review-rc4-gemma-postfix | gemma-4-31B-it | 9-rootcause | clean | 0 |
| review-rc4-qwen38 | qwen38 | 9-rootcause | findings | 1 |
| review-rctool-5-errors | qwen38 | 5-errors | clean | 0 |
| review-rctool-6-stats | qwen38 | 6-stats | clean | 0 |
| review-rootcause-gemma-4-31B-it | gemma-4-31B-it | 1-spec | clean | 0 |
| review-stats-excl-qwen38 | qwen38 | 3-data-io | findings | 1 |
| review-treatment-gemma | gemma | 8-treatment | findings | 1 |
| review-treatment-qwen38 | qwen38 | 8-treatment | findings | 1 |
