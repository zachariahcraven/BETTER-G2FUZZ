# BETTER-G2FUZZ

Fork of [G2FUZZ](https://github.com/G2FUZZ/G2FUZZ) ([paper](https://arxiv.org/abs/2501.19282)) for a research project at
Montana State University. Goal: replace G2Fuzz's random generator selection with a multi-armed bandit scheduler.

G2FUZZ has an LLM write Python generators for an input format, fuzzes their output with AFL++ 4.32c, and has the
LLM mutate the generators when coverage stalls.

## Quick start (Tempest)
First time only: [Tempest setup](#tempest-setup) steps 1–6. Then:

```bash
ssh tempest
cd /home/group/csci-591-automated-vulnerability-discovery/students/WORKING-BETTERG2FUZZ
scripts/fuzz llm status                    # the team's model server; none yet? see step 8
scripts/fuzz reuse example $USER-try       # the example run's seeds + generators: skips seed generation
scripts/fuzz run $USER-try 300 --test      # ~5 min, with an LLM step
scripts/fuzz watch $USER-try               # Ctrl-C closes it; the run keeps going
```

Campaign folders are shared: put your NetID (`$USER`) in each name.

More: [Step II](#step-ii-run-a-campaign), [docs/EXAMPLE_RUN.md](docs/EXAMPLE_RUN.md) (a real run, start to finish).
Local runs: [Local setup](#local-setup). Studies (design, launch scripts, results): [experiments/](experiments/README.md).

Branches: `dev` is the team's working branch (one shared copy on Tempest). `exploration` keeps the October 2026 experiments as a record. `main` tracks the upstream version.

# How to use it
`scripts/fuzz` runs the upstream steps below for you, the same way in both places. Run every command from the repo root.

|  | Local | Tempest |
| --- | --- | --- |
| Runs in | Docker image `g2fuzz:dev` | Slurm job per campaign, Apptainer image `g2fuzz.sif` |
| LLM | CatChat (`gpt-oss:120b`), free key | the team's Qwen3.8 server (`Qwen3.8-27B-FP8-nothink`), one per experiment |
| Setup | [Local setup](#local-setup), ~30 min | [Tempest setup](#tempest-setup) steps 1–6, ~15 min |

## Step I: Preparation

### Local setup
Tested on an arm64 Mac.

**1. Install Docker**

| OS | Install |
| --- | --- |
| macOS | `brew install docker colima`, then `colima start --cpu 4 --memory 8 --disk 60` |
| Linux | Docker Engine, then `sudo usermod -aG docker $USER` and log in again |
| Windows | Docker Desktop with WSL2. Clone the repo and run every command inside WSL |

Docker needs about 8 GB of RAM. On macOS, run `colima start` after each reboot and `colima stop` when you're done.

**2. Get the code**

```bash
git clone https://github.com/zachariahcraven/BETTER-G2FUZZ.git
cd BETTER-G2FUZZ
```

**3. Get a CatChat key:** follow [docs/CATCHAT_API_KEY.md](docs/CATCHAT_API_KEY.md), including its test step. The key
goes in `~/.secrets/catchat.key`. Off campus, connect to the MSU VPN.

**4. Build the image** (15–30 min the first time)

```bash
docker build -f docker/Dockerfile.g2fuzz -t g2fuzz:dev .
```

Rebuild after changing `afl/src/`, `afl/include/` or the Python files in `g2fuzz/`. Next: [Step II](#step-ii-run-a-campaign)
(locally there is no `example` campaign to reuse, so the first run includes seed generation: ~25 min).

### Tempest setup
Tempest can't reach CatChat, so runs use our own model server. Teammates: steps 1–6. Step 7 is the maintainer's;
step 8 is starting an experiment's server (no setup needed). Official docs: [Tempest](https://www.montana.edu/uit/rci/tempest).

**1. Connect the VPN.** SSH needs it, even on MSU-Secure Wi-Fi:
Cisco Secure Client → `vpn.msu.montana.edu` → your student or employee group.
No VPN? The web shell at <https://tempest-web.msu.montana.edu> works without it:

![Web shell](docs/img/tempest/01-web-shell.webp)

**2. Make an SSH key.** Only the `.pub` file leaves your computer.

```console
$ ssh-keygen -t ed25519 -C "<netid>@tempest" -f ~/.ssh/id_ed25519_tempest
$ pbcopy < ~/.ssh/id_ed25519_tempest.pub        # copies the public key (Linux/WSL: cat it, copy by hand)
```

**3. Add it on Tempest.** Sign in at <https://tempest-web.msu.montana.edu>, then paste it into `~/.ssh/authorized_keys`.
No `.ssh` folder or `authorized_keys`? Create them with **New Directory** / **New File**.

![Files: show dotfiles, open .ssh](docs/img/tempest/02-files-dotfiles.webp)

![authorized_keys: Edit](docs/img/tempest/03-authorized-keys.webp)

![Paste and save](docs/img/tempest/05-edit-authorized-keys.webp)

**4. Tell SSH about Tempest.** Add to `~/.ssh/config`:

```
Host tempest
  HostName tempest-login.msu.montana.edu
  User <netid>
  IdentityFile ~/.ssh/id_ed25519_tempest
  IdentitiesOnly yes
  AddKeysToAgent yes
  IgnoreUnknown UseKeychain
  UseKeychain yes
```

**5. Connect and check your accounts.**

```console
$ ssh tempest
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
[<netid>@tempest-login ~]$ sacctmgr -nP show assoc user=$USER format=account
group-csci-591-automated-vulnerability-discovery
priority-csci-591-automated-vulnerability-discovery
```

Type `yes` only if the fingerprint is `SHA256:7mk+Xk/AepBmtj03PHQaiZJBnNnWWAJDSFtOJy6wy1Q` (ED25519; older clients may
show ECDSA `SHA256:PyOIbM6dL+Wks93FQqXjJoeo28aquaCe8A5kLGqFm8o`). Asked once per computer.

**6. Go to the shared copy.** The team runs everything from one copy on `dev`: one image, one `eval/`.

```console
$ cd /home/group/csci-591-automated-vulnerability-discovery/students/WORKING-BETTERG2FUZZ
$ git config --global --add safe.directory "$PWD"     # one time: lets git work in a folder another user owns
$ scripts/fuzz account
group-csci-591-automated-vulnerability-discovery
```

Don't switch its branch: that changes the code for everyone. Settings are automatic; override in `~/.bashrc` only if needed:

| Variable | Default on Tempest |
| --- | --- |
| `G2F_ACCOUNT` | `group-csci-591-automated-vulnerability-discovery` (never another group's account) |
| `G2F_PARTITION` | `fairshare` |
| `G2F_CPUS`, `G2F_MEM` | `2`, `4G` per job |
| `G2F_BASE_URL`, `G2F_KEY` | the team's running `llm` server (step 8) |

**7. Get the image (maintainer only).** It's already in the shared copy. Tempest can't build Docker images, so one
person builds it on a Mac. One time:

```bash
brew install docker-buildx
mkdir -p ~/.docker/cli-plugins && ln -sf "$(brew --prefix)/bin/docker-buildx" ~/.docker/cli-plugins/
colima stop && colima start --vz-rosetta        # fast x86_64 builds
```

After each code change, commit, then from the Mac repo (VPN on, ~10 min): `scripts/tempest-image`.
It replaces `g2fuzz.sif` in the shared copy, writes the git version to `g2fuzz.sif.version`, and refuses while
anyone's campaigns run. The image holds the code: `git pull` on Tempest alone changes nothing.

**8. The model server: one per experiment.** One person starts it; everyone's runs find it. It serves
`Qwen3.8-27B-FP8-nothink` with vLLM from the shared `students/shared-models` folder, so there's nothing to download.
Thinking is off: G2Fuzz gives up on an LLM call after 300 s. Qwen won our model bake-off against `gpt-oss:120b` and
`llama3:70b`: the only one to finish seed generation in every run (20–40 min), and the most coverage after it on
mp42aac and pdftotext (about even with gpt-oss on jhead).

| Command | Does |
| --- | --- |
| `scripts/fuzz llm start [hours]` | 1 A40 on the class priority account: starts right away (default 24 h; the class has 2 GPUs) |
| `scripts/fuzz llm start [hours] h100` | 1 H100 on `gpufairshare`: uses no class GPU, but may wait hours or days |
| `scripts/fuzz llm status` | The team's server: owner, queued, loading or ready, time left |
| `scripts/fuzz llm stop` | Stops your server. Refuses while anyone's campaigns run |

`start` refuses while a team server is up. Start it for longer than the experiment's runs (`run` warns if it would
stop first) and stop it when done. Speed: an A40 has no native FP8, so calls take ~2.5× longer than on an A100/H100
(median ~50 s); a long generator rewrite can pass G2Fuzz's 300 s limit, and G2Fuzz then retries it. `~/llm/VERSIONS.txt` records the model revision and GPU for the write-up.

### The setting files
Upstream asks you to set up three files by hand; `scripts/fuzz new` does it for each campaign in `eval/<campaign>/`:
- `openai_key.txt`: the key, mounted read-only (local: `~/.secrets/catchat.key`; Tempest: `~/llm/dummy.key`).
- `program_to_format.json`: copied from `g2fuzz/program_to_format.json`. `--program` must be one of its keys.
- `model_setting.json`: written from `G2F_MODEL` (default: the team server's `Qwen3.8-27B-FP8-nothink` on Tempest,
  CatChat's `gpt-oss:120b` locally).

G2Fuzz and the targets are compiled inside the image (`make source-only`, then `/targets/<name>.afl` and `.cmp`), as
upstream describes. `scripts/fuzz help` lists all settings (key, server, model, target, image).

## Step II: Run a campaign
Seed generation (upstream Step II) and fuzzing (upstream Step III) run as one campaign:

```bash
scripts/fuzz llm status               # Tempest only: "ready"? No server: scripts/fuzz llm start 2
scripts/fuzz new $USER-first
scripts/fuzz run $USER-first 900 --test
scripts/fuzz watch $USER-first
```

- Seed generation runs first (15–20 min), then fuzzing for 900 s.
- `--test` fires the LLM step (`llmGen-M`) after 10 s without new coverage, so you see one. Never use it for experiments.
- Ctrl-C closes `watch`; the run keeps going. When it finishes: `scripts/fuzz results $USER-first`.
- On Tempest the job shows up as `g2f-<netid>-first` (the server as `llm-serve`). A job that ends at once: read
  `eval/<campaign>/slurm-<jobid>.out` (it checks the LLM first).

![Active Jobs](docs/img/tempest/04-active-jobs.webp)

### Commands

| Command | Does |
| --- | --- |
| `new [name]` | Create a campaign in `eval/` (default name `jhead-MMDD-HHMM`) |
| `reuse <from> [name]` | New campaign with `<from>`'s seeds and generators. Skips seed generation (15–20 min) |
| `run <name> [secs] [--test]` | Background run: seed generation if needed, then fuzz (default 3600 s). Tempest: a Slurm job |
| `run <name> [secs] --afl` | The paper's baseline, AFL++(cmplog): same fuzzer, no LLM, stock seeds. Needs no server |
| `shell <name>` | Shell in the image, in that campaign (Tempest: an interactive 4 h job) |
| `watch <name>` | Live view (Ctrl-C closes it; the run keeps going) |
| `status [name]`, `results <name>`, `list` | Numbers once, final summary, all campaigns |
| `stop <name>` | Stop the run (Tempest: `scancel`, after copying the output back). Files stay |

On Tempest, run `watch`, `status` and `list` on the login node. What you see (a 5-minute `--test` run):

```console
$ scripts/fuzz status llmtest2
llmtest2  [ended]

phase        finished
run time     0:05:00
corpus       732
crashes      9
coverage     634 edges (32.31%)
speed        2290.12 execs/s, 487681 total
last find    1s ago   (LLM step after 10s without one)
llmGen-M     1 steps
LLM calls    68 (68 ok)

$ scripts/fuzz results llmtest2
...
llmGen-M steps    : 1
LLM calls         : 68 (68 ok, 0 errors)
generator lineage : {"jpg-9.py": ["jpg-36.py"]}
crashes dir       : eval/llmtest2/jhead_output/default/crashes
```

`generator lineage` shows which generator the LLM step mutated into which.

### Output files
Everything is in `eval/<campaign>/` and stays after the run. AFL++ writes `jhead_output/` on fast local disk (it is
5–8x slower on a network home or shared folder); the copy in `eval/` is updated every 30 s and when the run ends or
is stopped. On Tempest, pip installs from generators go to `eval/<campaign>/.pyuser/`.

| Path | Contents |
| --- | --- |
| `seedgen.log`, `fuzz.log` | Logs from seed generation and fuzzing |
| `llm_calls.jsonl` | One line per LLM request: latency, success or error, retry attempt |
| `jhead_output/default/queue/` | Corpus. `orig:jpg-N_k` entries came from G2Fuzz generators |
| `jhead_output/default/crashes/` | Crashing inputs |
| `jhead_output/default/generators/` | Python generators the LLM wrote |
| `jhead_output/default/fuzzer_stats`, `plot_data` | Coverage and speed (`afl-plot` graphs these) |
| `jhead_output/default/mutation_log/relationship.json` | Which generator was mutated into which |
| `jhead_output/default/gen_seeds_energy_log` | Seeds added and time spent in the LLM |
| `job.sbatch`, `run.sh`, `slurm-<jobid>.out` | Tempest only: the Slurm job |

Debugging the pipeline? The raw commands `scripts/fuzz` runs: [docs/BY_HAND.md](docs/BY_HAND.md).

## Day to day

**Alias and tab completion (zsh):**

```bash
printf '%s\n' "alias fuzz='$PWD/scripts/fuzz'" "source '$PWD/scripts/fuzz-completion.zsh'" >> ~/.zshrc && source ~/.zshrc
```

**Change the code,** then rebuild the image (local: `docker build`, Tempest: `scripts/tempest-image`) and start a
new campaign:

| What | File |
| --- | --- |
| Generator and mutator selection (scheduler hook) | `g2fuzz/generator_mutation.py` |
| Seed generation | `g2fuzz/program_gen.py` |
| LLM calls, retries, logging | `g2fuzz/py_utils/llm_utils.py` |
| When `llmGen-M` triggers | `afl/src/afl-fuzz.c` (search `G2F:`) |
| Image contents and targets | `docker/Dockerfile.g2fuzz` |

**The paper's targets** (Tempest): `paper/` has the paper's exact versions (all 25 UNIFUZZ, FuzzBench and MAGMA
projects), `latest/` the newest releases. Each target's arguments and seeds come from the folder; `ls` it (`*.afl`) for
the names. G2FUZZ-upgradedAFL uses its own build, `g2f-targets/afl503/paper`. Build scripts: `targets/paper/`
(`build-paper.sh`, tested by `tests/image/test_paper_targets.sh`). Keep both set for `new` and `run`:

```bash
export G2F_TARGETS=/home/group/csci-591-automated-vulnerability-discovery/students/g2f-targets/paper
export G2F_TARGET=libpng_libpng_read_fuzzer
scripts/fuzz new png1 && scripts/fuzz run png1 3600
```

**Results on the Mac:**

```bash
rsync -a tempest:/home/group/csci-591-automated-vulnerability-discovery/students/WORKING-BETTERG2FUZZ/eval/<campaign> eval/
scripts/fuzz results <campaign>
```

**Tempest's model from the Mac** (VPN on), through a tunnel:

```bash
ssh -f -N -L 8000:$(ssh tempest /home/group/csci-591-automated-vulnerability-discovery/students/WORKING-BETTERG2FUZZ/scripts/fuzz llm host) tempest
G2F_BASE_URL=http://host.docker.internal:8000/v1 G2F_MODEL=Qwen3.8-27B-FP8-nothink scripts/fuzz run <campaign>
pkill -f "ssh -f -N -L 8000"      # close it afterwards
```

**Teammates can't open your files?** AFL++ writes its output readable only by you. `scripts/group-perms` gives
the group access to everything you own in the shared folder ([docs/GROUP_PERMISSIONS.md](docs/GROUP_PERMISSIONS.md));
`scripts/fuzz` already does it for each run's output.

**Git:**
- Work on `dev`. The shared copy on Tempest stays on `dev` (everyone runs from it).
- `eval/` and keys are git-ignored. Don't force-add them.
- Linux Docker: campaign files are owned by root. Delete them with `sudo`.

**Push to GitHub from Tempest (optional):** [docs/GITHUB_FROM_TEMPEST.md](docs/GITHUB_FROM_TEMPEST.md).

# Contact

From the upstream README (the G2FUZZ authors). If you have any questions or suggestions, feel free to contact me via email: [kzhangcl@connect.ust.hk](mailto:kzhangcl@connect.ust.hk)
