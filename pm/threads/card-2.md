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
