# A04-lists-13-6h

Not a comparison. It makes the queues from which `build/targets/build-uncovered.sh` builds the `uncovered`
mutator's lists for the 13 paper targets that A00 did not run: control arm only, 6 h, 2 reps, gpt-oss-20b.

After it ends:

    build/targets/build-uncovered.sh experiments/A04-lists-13-6h/campaigns/control $(grep -v '^#' experiments/A04-lists-13-6h/launch/targets.txt)

Then all 28 paper targets have a `<target>.uncovered.json`, and the check round can run `uncovered` on them.
