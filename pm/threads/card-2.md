# card-2: Relaunch A02, then A00 freetype2 reruns, on Tempest (owned by session alfred-tweak-rounds-study)

## Note nom-nom 2026-11-13 17:15
**Owner: session alfred-tweak-rounds-study.** No other session should scancel, sbatch, move campaign folders or git checkout on Tempest without checking with it or the user: two relaunches would double-launch campaigns. Waits on card-1.

State (2026-11-13 15:30 MST): queue empty, no LLM server, no watcher. Tempest outage 10:35-12:41 (RCI: "a configuration error") killed all running jobs.
- A00-baseline-6h: 285 campaigns finished cleanly before the outage. 15 freetype2 campaigns were killed at ~4.6 h of 6 h, read "done (short)", NOT moved yet: the restart needs `--retry-failed`.
- A02-rfdm-all-formats-6h: 17 campaigns moved to `campaigns/.retried/` (see `.retried/MOVED.txt`): 12 outage-hit + 3 earlier ALF-1 crashes via `--retry-failed`, 2 by hand (control/imginfo-r2, rfdm-all/gdk-pixbuf-pixdata-r5). Plus 8 never launched.

Steps, in `~/csci-591-automated-vulnerability-discovery/students/alfred`:
1. `git checkout -q --detach 01db4f3` (scripts/study refuses when image commit != HEAD; image `build/g2fuzz.sif` = 01db4f3).
2. `STUDY_EXTRA_ACCOUNT=priority-csci-591-automated-vulnerability-discovery STUDY_EXTRA_MAX=120 scripts/study start A02-rfdm-all-formats-6h --servers --background` first (A02 owns the 48 h server).
3. Wait for `campaigns/study-driver-<job>.log` to show `== A02`, then the same command for `A00-baseline-6h` with `--retry-failed`.
4. `git checkout -q alfred`.
5. Watcher: `sbatch -A group-csci-591-automated-vulnerability-discovery -p fairshare -c 1 --mem 1G -t 2-00:00:00 -J watch-alfred -o ~/.cache/alfred-watch/watch-%j.out --wrap "bash ~/.cache/alfred-watch/watch3.sh"` (events in `~/.cache/alfred-watch/events.log`).

Expect: A00 freetype2 reruns ~6 h. A02 needs fresh seed generation (max 4 at a time) for 25 campaigns, about a day after launch.

Full detail: `~/.claude/projects/-Users-zachcraven-Desktop-Fall2026-Cyber-papers/memory/alfred-handoff-2026-11-13.md`.

## Note nom-nom 2026-11-13 18:09
2026-11-13 18:10: the DNS blocker has a verified workaround (details in card-1's notes). Before step 2, in the same shell:

```
export LOCALDOMAIN=rci.montana.edu APPTAINERENV_LOCALDOMAIN=rci.montana.edu
```

Optionally also `export SBATCH_NO_REQUEUE=1` (card-8: the 01db4f3 checkout does not pass `--no-requeue`). Step 1's check then becomes: `LOCALDOMAIN=rci.montana.edu getent hosts gpu056` on a compute node. Also note card-12: the 01db4f3 image still has the worker crash OURS-7.

## Note nom-nom 2026-11-13 18:28
**Relaunched 2026-11-13 18:26-18:29 MST by nom-nom, on the user's go** (session alfred-tweak-rounds-study is no longer running). DNS was still broken; the workaround from card-1 was used.

In one shell on the login node, in `students/alfred`:
1. `git checkout -q --detach 01db4f3`; dry runs of both starts matched the plan (A02: 25 campaigns to run; A00: the 15 freetype2).
2. `export LOCALDOMAIN=rci.montana.edu APPTAINERENV_LOCALDOMAIN=rci.montana.edu SBATCH_NO_REQUEUE=1`
3. A02: `STUDY_EXTRA_ACCOUNT=priority-csci-591-automated-vulnerability-discovery STUDY_EXTRA_MAX=120 scripts/study start A02-rfdm-all-formats-6h --servers --background` -> driver job **1279637** (on epyc001, a bad-DNS node: it passed the account check that killed 1275504) and gpt-oss-20b server job **1279638** on gpu056 (qc-h100, 48 h).
4. A00: the same with `--retry-failed` -> moved the 15 freetype2 campaigns to `campaigns/.retried/` (MOVED.txt), driver job **1279658**.
5. `git checkout -q alfred` (back at f8ddcbb, clean).
6. Watcher: job **1279660** (`watch-alfred`, events in `~/.cache/alfred-watch/events.log`).

Logs: `experiments/<study>/campaigns/study-driver-<job>.log`. Stop a study: `scancel <driver job>`.

## Note nom-nom 2026-11-13 18:40
**Confirmed running, 18:40 MST.** 23 jobs running, none pending: 2 drivers, 1 LLM server (gpu056), 1 watcher, 15 A00 freetype2 campaigns (jobs 1279740-1279754, reusing the 42 shared seeds), 4 A02 campaigns in seed generation (1279719-1279722; A02 runs at most 4 seed generations at a time, 21 still to launch).

Campaigns landed on bad-DNS nodes (epyc001, epyc019, epyc036) and their LLM calls succeed: the four A02 seed generations have 23 to 29 calls each, all `ok`; the continuous freetype2 runs have their first calls, all `ok`. Control and fast-stall freetype2 have made no calls yet, as expected (they wait for a stall). No "can't reach" lines in any job output.

**Expected:** A00's freetype2 reruns end about 00:40 MST on 2026-11-14 (6 h). A02 needs seed generation for 25 campaigns, 4 at a time, then 6 h each: the earlier estimate was midday to afternoon of 2026-11-14.

**Not rerun:** continuous mp42aac-r3/r4/r5 (card-12, the user has not decided).

## Note nom-nom 2026-11-13 18:40
Brief: now: relaunched 18:26 with the DNS workaround; 15 A00 + 4 A02 campaigns running, LLM calls ok
next: A00 reruns end ~00:40 on 11-14; A02 ends around midday 11-14; then final compare (card-3)
you: nothing (optional: decide the 3 mp42aac reruns, card-12)

## Note nom-nom 2026-11-14 19:30
**A02 ended (checked 2026-11-14 19:29 MST).** Driver 1279637 finished and stopped the LLM server (1279638); only the watcher (1279660) is still in the queue.

- 39 of 40 campaigns done at full length, 0 failed.
- 1 short: `rfdm-all/gdk-pixbuf-pixdata-r5`, job 1280094 on epyc020, afl-fuzz aborted at 17,090 s of 21,600 with "Incorrect fuzzing setup detected ... incorrectly instrumented shared libraries (5684 of 5683/5696)". That is ALF-1, fixed only in the new target builds (card-5), so a retry on the 01db4f3 image can hit it again.
- A00: 315 of 315 done (card-3).
- Not done: `scripts/compare` for A02; the watcher is not cancelled.

## Note nom-nom 2026-11-14 19:30
Brief: now: A02 ended: 39/40 done, 1 short (rfdm-all gdk-pixbuf r5, ALF-1 abort at 17,090 s)
next: A02 compare and stop the watcher, when you say
you: retry that one campaign (about 9 h, delays the deploy) or accept 4 of 5 reps

## Note nom-nom 2026-11-14 19:36
**A02 closed out (default decisions, 2026-11-14, under the user's "decide from the evidence" instruction).**

- The short campaign `rfdm-all/gdk-pixbuf-pixdata-r5` is **not retried**: ALF-1 can cut it again on the old builds, a retry costs about 9 h of deploy delay, and gdk-pixbuf is the one target where rfdm-all already looks better (it cannot flip the round).
- `scripts/compare` and `scripts/lineage` run; reports in `experiments/A02-rfdm-all-formats-6h/results/` on Tempest.
- **rfdm-all dropped**: 2 targets higher, 2 lower, median ratio 0.997, p = 0.562; about 3 times the seed-generation LLM calls; 2 OOM kills. gdk-pixbuf-pixdata alone is higher (1.027, p = 0.048, 4 reps).
- Rounds log row for A02 added in `docs/ALFRED-ROUNDS.md`.
- Watcher job 1279660 left running (1 core, ends by itself 2026-11-15 18:28).

## Note nom-nom 2026-11-14 19:36
Files: docs/ALFRED-ROUNDS.md

## Note nom-nom 2026-11-14 19:36
Brief: now: A02 done and analysed: rfdm-all dropped (ratio 0.997, p 0.562); short run not retried
next: deploy window (card-5)
you: approve (commits the A02 row in docs/ALFRED-ROUNDS.md)

## Note nom-nom 2026-11-14 19:36
Review:
##### To check
- Open the diff of `docs/ALFRED-ROUNDS.md`: one new table row (A02-rfdm-all-formats-6h).
- On Tempest: `less experiments/A02-rfdm-all-formats-6h/results/compare.md`, section "Decisions" says drop.
##### Changed
Relaunch finished: A00 315/315, A02 39/40 (1 cut short by ALF-1, not retried).
A02 analysed: rfdm-all dropped (median ratio 0.997, p 0.562, 3x set-up LLM calls).
Added A02's row to the Rounds log.
