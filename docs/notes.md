# Notes: the scripts, command by command

```console
$ source scripts/enable-completion
enable-completion: added to ~/.bashrc: eval "$(/home/group/csci-591-automated-vulnerability-discovery/students/BETTERG2FUZZ/scripts/fuzz completion)"
enable-completion: on in this shell too (try: fuzz run <Tab>)
```
Makes `fuzz` mean the repo's `scripts/fuzz` in every shell and turns on Tab completion for commands, campaigns, options and models.

```console
$ fuzz help
fuzz: shortcuts for G2Fuzz campaigns on Tempest (Slurm + Apptainer). See README.md (Step II).

Usage: scripts/fuzz <command> [args]

  new     [name] [--model M]      Create a campaign folder (in experiments/practice/campaigns/ by default) that
                                  uses model M (default Qwen3.8-27B-FP8). Default name: <netid>-<target>-MMDD-HHMM
  reuse   <from> [name] [--model M]  New campaign with seeds + generators copied from campaign <from>
  run     <name> [secs] [--test|--afl] [--scheduler S]  Background run: seed generation (if no seeds yet),
                                  then fuzz for <secs> seconds (default 3600)
…
```
Lists every command, option and setting when you can't remember one.

```console
$ fuzz account
group-csci-591-automated-vulnerability-discovery
```
Shows which Slurm account your campaigns are charged to.

## 2. The model server

```console
$ fuzz llm start 2
submitted Qwen3.8-27B-FP8-nothink server job 950060 (a40, 2 h, account priority-csci-591-automated-vulnerability-discovery). Ready ~5 min after it starts: scripts/fuzz llm status
```
Starts the LLM that G2FUZZ campaigns talk to (Qwen3.8 on one class A40 for 2 hours); start it longer than your runs.

```console
$ fuzz llm start 48 h100 --model phi-4
submitted phi-4 server job 950061 (h100, 48 h, account group-csci-591-automated-vulnerability-discovery). Ready ~5 min after it starts: scripts/fuzz llm status
```
Starts a different model from `shared-models` (here on an H100 instead of a class A40), e.g. for the model sweep.

```console
$ fuzz llm status
Qwen3.8-27B-FP8-nothink, n59m742's server:
     JOBID     STATE        TIME   TIME_LEFT NODELIST
    950060   RUNNING        0:37     1:59:23 gpu040
loading the model (~5 min)

$ fuzz llm status
Qwen3.8-27B-FP8-nothink, n59m742's server:
     JOBID     STATE        TIME   TIME_LEFT NODELIST
    950060   RUNNING     1:03:28       56:32 gpu040
ready: Qwen3.8-27B-FP8-nothink on gpu040
```
Tells you whether the server is queued, loading or ready; wait for `ready:` before you `run`.

```console
$ fuzz llm host
gpu040:30060
```
Gives the server's node and port, e.g. for an SSH tunnel from your Mac.

## 3. Make a campaign

```console
$ fuzz reuse example n59m742-try
created experiments/practice/campaigns/n59m742-try (target jhead, model Qwen3.8-27B-FP8-nothink)
copied 34 seeds and 32 generators from experiments/practice/campaigns/example
next: scripts/fuzz run n59m742-try [secs]
```
Makes a campaign that starts from `example`'s seeds and generators, so it skips seed generation (20 min to 2 h).

```console
$ fuzz new n59m742-fresh
created experiments/practice/campaigns/n59m742-fresh (target jhead, model Qwen3.8-27B-FP8-nothink)
next: scripts/fuzz run n59m742-fresh [secs]
```
Makes an empty campaign, so its run generates its own seeds with the LLM first (what a real experiment does).

```console
$ export G2F_TARGETS=/home/group/csci-591-automated-vulnerability-discovery/students/g2f-targets/paper
$ export G2F_TARGET=libpcap_fuzz_both
$ fuzz new n59m742-pcap
created experiments/practice/campaigns/n59m742-pcap (target libpcap_fuzz_both, model Qwen3.8-27B-FP8-nothink)
next: scripts/fuzz run n59m742-pcap [secs]
```
Makes a campaign for one of the paper's 28 targets instead of jhead (keep both exports set for `run`, `watch` and `results`).

## 4. Run it

```console
$ fuzz run n59m742-try 2400 --test
TEST MODE: llmGen-M after 10 s without new coverage (not for experiments)
reusing 34 seeds: fuzzing only
generator scheduler: ucb (exploration 1.0)
submitted Slurm job 950879 (fuzz 2400s, limit 70 min, account group-csci-591-automated-vulnerability-discovery). Watch it: scripts/fuzz watch n59m742-try
```
Runs a quick test where an LLM step (the UCB scheduler picking a generator to mutate) fires after 10 s without new coverage; never use `--test` for results.

```console
$ fuzz reuse example n59m742-random && fuzz run n59m742-random 2400 --test --scheduler random
created experiments/practice/campaigns/n59m742-random (target jhead, model Qwen3.8-27B-FP8-nothink)
copied 34 seeds and 32 generators from experiments/practice/campaigns/example
next: scripts/fuzz run n59m742-random [secs]
TEST MODE: llmGen-M after 10 s without new coverage (not for experiments)
reusing 34 seeds: fuzzing only
generator scheduler: random (upstream G2FUZZ; the default is ucb)
submitted Slurm job 950880 (fuzz 2400s, limit 70 min, account group-csci-591-automated-vulnerability-discovery). Watch it: scripts/fuzz watch n59m742-random
```
Runs a second campaign with upstream G2FUZZ's random generator pick instead of our UCB scheduler, to compare the two (a campaign runs only once).

```console
$ fuzz run n59m742-pcap 600 --test
TEST MODE: llmGen-M after 10 s without new coverage (not for experiments)
no seeds yet: seed generation first (20 min to 2 h, depending on the target), then fuzzing
generator scheduler: ucb (exploration 1.0)
submitted Slurm job 950881 (fuzz 600s, limit 160 min, account group-csci-591-automated-vulnerability-discovery). Watch it: scripts/fuzz watch n59m742-pcap
```
Runs a new campaign end to end: the LLM writes generators and seeds first, then AFL++ fuzzes.

```console
$ fuzz new n59m742-afl && fuzz run n59m742-afl 300 --afl
created experiments/practice/campaigns/n59m742-afl (target jhead, model Qwen3.8-27B-FP8-nothink)
next: scripts/fuzz run n59m742-afl [secs]
AFL++(cmplog) baseline: stock seeds (/AFLplusplus/testcases/images/jpeg), no LLM
submitted Slurm job 949782 (fuzz 300s, limit 35 min, account group-csci-591-automated-vulnerability-discovery). Watch it: scripts/fuzz watch n59m742-afl
```
Runs the paper's baseline (plain AFL++ with cmplog, no LLM), which needs no model server.

```console
$ fuzz run n59m742-try 900 --test
fuzz: the Qwen3.8-27B-FP8-nothink server on gpu040 is still loading the model (~5 min after it starts). Run this again once scripts/fuzz llm status says ready
```
This is what `run` says if the server isn't ready yet; nothing was submitted, so just run it again in a few minutes.

## 5. Watch it and read the results

```console
$ fuzz watch zach-ubc
zach-ubc  [running]

phase        fuzzing
run time     0:17:37
corpus       911
crashes      10
coverage     572 edges (29.15%)
speed        2184.11 execs/s, 1132332 total
last find    483s ago   (LLM step after 10s without one)
llmGen-M     0 steps
scheduler    ucb (exploration 1.0)
LLM calls    4 (4 ok)   last: ok after 137.48s, 210s ago

Ctrl-C closes this view; the run keeps going.
```
Shows a running campaign live (refreshed every second); Ctrl-C only closes the view.

```console
$ fuzz status jhead-1029-1841
jhead-1029-1841  [running]

phase        fuzzing
run time     0:30:00
corpus       1458
crashes      18
coverage     654 edges (33.33%)
speed        1997.61 execs/s, 3107290 total
last find    9s ago   (LLM step after 300s without one)
llmGen-M     0 steps
scheduler    random
LLM calls    0
```
Prints the same numbers once, e.g. to paste somewhere or to check a campaign quickly.

```console
$ fuzz list
CAMPAIGN                   SEEDS  GENERATORS  FUZZED STATE
example                    34     32          yes    ended
jhead-1029-1841            34     32          yes    running
t19z813-ucb-smoke          34     33          yes    ended
zach-ubc                   34     32          yes    running
```
Lists every campaign in the practice folder with its run state, so you can find a name.

```console
$ fuzz results jhead-1029-1841
== jhead-1029-1841
run_time          : 1742
execs_done        : 3011333
execs_per_sec     : 1727.78
corpus_count      : 1447
stability         : 100.00%
saved_crashes     : 17
edges_found       : 653
total_edges       : 1962
generators        : 32
scheduler         : random
llmGen-M steps    : 0
LLM calls         : 0 (0 ok, 0 errors)
crashes dir       : experiments/practice/campaigns/jhead-1029-1841/jhead_output/default/crashes
```
Gives the summary of a campaign (coverage, crashes, LLM use) and where its crashing inputs are.

## 6. Hands on, and stopping a run

```console
$ fuzz shell jhead-1029-1841
Apptainer> ls
fuzz.log        image-version.txt    jhead_output  model_setting.json  program_to_format.json  slurm-950669.out
generator_scheduler  initial_seeds    job.sbatch    openai_key.txt     run.sh         slurm.jobid
Apptainer> /targets/jhead.asan jhead_output/default/crashes/id:000000*
# (prints AddressSanitizer's report if the crash reproduces; nothing if it doesn't)
Apptainer> exit
```
Opens a terminal inside the run's container, in the campaign folder, to replay a crash on the sanitizer build or try commands by hand (exit when done; it holds a node).

```console
$ fuzz stop rf-stop
cancelled Slurm job 949783
```
Stops a running campaign early; AFL++ still writes its final stats and the files stay.

## 7. Stop the server

```console
$ fuzz llm stop
fuzz: campaigns of n59m742 are still queued or running on it. Stop them first, or: scancel 950060

$ fuzz llm stop
stopped: Qwen3.8-27B-FP8-nothink (job 950060)
```
Frees the GPU when you're done; it refuses while anyone's campaigns still use the server.

## 8. A study: the model sweep (one model against the 15 targets)

```console
$ DRY=1 experiments/02-model-sweep/launch/sweep start phi-4
note: the phi-4 server isn't ready (dry run goes on)
== phi-4, rep 1, 21600 s each, scheduler ucb, at most 4 in seed generation
  would launch jhead-r1 (21600 s)
  would launch gdk-pixbuf-pixdata-r1 (21600 s)
…
```
Shows what a sweep would launch without launching anything.

```console
$ experiments/02-model-sweep/launch/sweep start phi-4 --wait
== phi-4, rep 1, 21600 s each, scheduler ucb, at most 4 in seed generation
  jhead-r1: no seeds yet: seed generation first (20 min to 2 h, depending on the target), then fuzzing
  jhead-r1: generator scheduler: ucb (exploration 1.0)
  jhead-r1: submitted Slurm job 951001 (fuzz 21600s, limit 690 min, account group-csci-591-automated-vulnerability-discovery). Watch it: scripts/fuzz watch jhead-r1
…
2026-10-30 09:10:00 waiting for seed generation to finish; still to launch: mp3gain mp42aac …
```
Launches all 15 campaigns of one model over a few hours, at most 4 seed generations at a time (run it in tmux; it never launches a campaign twice).

```console
$ experiments/02-model-sweep/launch/sweep status Qwen3.8-27B-FP8
== Qwen3.8-27B-FP8, rep 1 (/home/group/csci-591-automated-vulnerability-discovery/students/BETTERG2FUZZ/experiments/02-model-sweep/campaigns/Qwen3.8-27B-FP8)
target                         state         edges  crashes  execs/s  run_s  generators  llm_steps  llm_calls
jhead                          not launched                                  0                      0
gdk-pixbuf-pixdata             not launched                                  0                      0
…
```
Shows one line per target (state, coverage, crashes, LLM use) for a model's sweep.

```console
$ experiments/02-model-sweep/launch/sweep csv Qwen3.8-27B-FP8 0
# (the launcher's 600 s test, rep 0; those campaigns are now in setup/sweep-test/)
model,target,state,edges,crashes,execs/s,run_s,generators,llm_steps,llm_calls
Qwen3.8-27B-FP8,jhead,done,498,18,2770.42,600,16,0,23
Qwen3.8-27B-FP8,gdk-pixbuf-pixdata,done,1367,26,664.88,600,81,0,110
```
Prints the same table as CSV; redirect it to `experiments/02-model-sweep/results/<model>-r1.csv` when a model is done.

## 9. Maintenance

```console
$ scripts/group-perms
# (expected, from the script; not rerun today: it walks the whole students folder)
group-perms: the group now has full access to your files in /home/group/csci-591-automated-vulnerability-discovery/students
```
Gives teammates read/write access to everything you own in the shared folder, when they can't open your files.

```console
mac$ G2F_TEMPEST_HOST=tempest-nextgen scripts/tempest-image
== building the x86_64 image
== copying it to tempest-nextgen (about 600 MB)
== converting it on a compute node
g2fuzz.sif is now: 66033fa built 2026-10-29 15:03
```
Rebuilds `g2fuzz.sif` from the Mac (VPN on, colima running) after a commit that changes `afl/` or `g2fuzz/`, such as the scheduler.
