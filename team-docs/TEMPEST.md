# Running on Tempest

Tempest is MSU's HPC cluster. `scripts/fuzz` works the same there.
Without Docker, it runs each campaign as a Slurm job in an Apptainer image.
Tempest can't reach CatChat, so campaigns use our own copy of the same model on a Tempest GPU (section 5).
Official docs: [Tempest](https://www.montana.edu/uit/rci/tempest).

## 1. Log in and check your Slurm accounts

SSH needs the MSU VPN, even on campus Wi-Fi (MSU-Secure is not enough).
Use Cisco Secure Client with server `vpn.msu.montana.edu` and your student or employee group.
Without the VPN, use the web shell at <https://tempest-web.msu.montana.edu> (Clusters → Tempest Login Shell Access).

SSH uses a key, not a password. One time, on your Mac:

```bash
ssh-keygen -t ed25519 -C "<netid>@tempest" -f ~/.ssh/id_ed25519_tempest
pbcopy < ~/.ssh/id_ed25519_tempest.pub
```

Paste the key as a new line in `~/.ssh/authorized_keys` on Tempest (web shell Files app, Show Dotfiles), then run
`chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` there. Add this to `~/.ssh/config` on the Mac:

```
Host tempest
  HostName tempest-login.msu.montana.edu
  User <netid>
  IdentityFile ~/.ssh/id_ed25519_tempest
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
```

Now `ssh tempest` logs in. Check your accounts:

```bash
sacctmgr -nP show assoc user=$USER format=account
```

| Account | Partitions |
| --- | --- |
| `group-<name>` | `fairshare`, `unsafe` (preemptible), `gpufairshare` (H100, not preemptible), `gpuunsafe` |
| `priority-<name>` | `priority`, `interactive` |

Dr. Revelle's accounts are `group-mattrevelle` and `priority-mattrevelle`. Ask him to add you.

## 2. Get the code

```bash
git clone https://github.com/zachariahcraven/BETTER-G2FUZZ.git && cd BETTER-G2FUZZ
```

No CatChat key is needed on Tempest. The local model takes any key (section 5).

## 3. Settings

None are needed. `scripts/fuzz` picks these by itself:

| Setting | Default on Tempest |
| --- | --- |
| Slurm account (`G2F_ACCOUNT`) | `group-mattrevelle` once you're in it, else your first `group-*` account. Check with `scripts/fuzz account` |
| Partition (`G2F_PARTITION`) | `fairshare` |
| LLM (`G2F_BASE_URL`, `G2F_KEY`) | The running `scripts/fuzz llm` server (section 5) |

Set a variable in `~/.bashrc` only to override it. If you do, and you have no `~/.bash_profile`, run
`cp -n /etc/skel/.bash_profile /etc/skel/.bashrc ~/` first, or login shells won't read `~/.bashrc`.

`G2F_CPUS` (default 2) and `G2F_MEM` (default 4G) set each job's size.

## 4. Get the image

Tempest can't build Docker images. Rootless Podman doesn't work on its home file system.
So the Mac builds an x86_64 image and Tempest converts it. One person does this for the team.

On the Mac, one time:

```bash
brew install docker-buildx
mkdir -p ~/.docker/cli-plugins && ln -sf "$(brew --prefix)/bin/docker-buildx" ~/.docker/cli-plugins/
colima stop && colima start --vz-rosetta        # Rosetta makes x86_64 builds fast
```

Each time the G2Fuzz code changes, from the repo on the Mac (VPN on, about 10 min):

```bash
scripts/tempest-image
```

It builds the image, copies it to Tempest, converts it to `g2fuzz.sif` and records the git version in
`g2fuzz.sif.version`. Each run copies that to `eval/<campaign>/image-version.txt`.
It refuses while campaigns are running, so an experiment never mixes code versions.
The image holds the G2Fuzz code, so `git pull` on Tempest alone doesn't change what runs.
Commit first: a version ending in `-dirty` had uncommitted changes.

## 5. Local LLM

Tempest can't reach CatChat (`catchat-api.msu.montana.edu` times out from all Tempest nodes).
Instead, a Slurm job serves `gpt-oss:120b`, the same model CatChat uses, with Ollama on one H100.
One server handles all campaigns. Calls take seconds (median 8 s, max 41 s in our tests).

One time (about 30 min, 65 GB in `~/llm/models`):

```bash
mkdir -p ~/llm/models && cd ~/llm
srun -A $(~/BETTER-G2FUZZ/scripts/fuzz account) -p fairshare -c 8 --mem 16G -t 180 bash -c '
  apptainer pull ollama.sif docker://ollama/ollama:latest
  export OLLAMA_MODELS=$HOME/llm/models OLLAMA_HOST=127.0.0.1:11434
  apptainer exec ollama.sif ollama serve & sleep 10
  apptainer exec ollama.sif ollama pull gpt-oss:120b'
echo ollama > dummy.key && chmod 600 dummy.key
```

Then, from the repo:

| Command | What it does |
| --- | --- |
| `scripts/fuzz llm start [hours]` | Starts the server for that long (default 24, up to 336). Ready about 4 min after it gets a GPU |
| `scripts/fuzz llm status` | Queued, loading, or ready, and the time left |
| `scripts/fuzz llm stop` | Stops it. Refuses while campaigns are queued or running |

`run` finds the server by itself and stops with a clear message if there is none.
Start the server for longer than your runs: a run keeps the server's address, so a new server can't take over mid-run.
`run` warns if the server would stop before the run ends.
Stop it when you're done, so the GPU doesn't sit idle.

Use the same server for every configuration in an experiment. `~/llm/VERSIONS.txt` records the Ollama
version, model digest and settings for the write-up. Pull the image and model only once, so they don't change mid-experiment.

From the Mac (with the VPN), an SSH tunnel reaches the same server:

```bash
ssh -f -N -L 11434:$(ssh tempest cat llm/server-host):11434 tempest
G2F_BASE_URL=http://host.docker.internal:11434/v1 G2F_KEY=~/.secrets/ollama.key scripts/fuzz run <campaign>
```

`~/.secrets/ollama.key` can hold any text. Close the tunnel afterwards with `pkill -f "ssh -f -N -L 11434"`.

## 6. First campaign

```bash
scripts/fuzz llm start 2
scripts/fuzz llm status                 # wait for "ready"
scripts/fuzz new first
scripts/fuzz run first 900 --test
scripts/fuzz watch first
```

Everything in [WORKFLOW.md](../WORKFLOW.md) works. These commands differ:

| Command | On Tempest |
| --- | --- |
| `run` | Submits a Slurm job. `eval/<campaign>/` gets `job.sbatch`, `run.sh` and the log `slurm-<jobid>.out` |
| `shell` | Interactive Slurm job (4 h) with `apptainer shell` |
| `stop` | `scancel`. The output is copied back first |
| `watch`, `status`, `list` | Show the job state from `squeue`. Run them on the login node |
| `llm`, `account` | Tempest only (sections 3 and 5) |

If a job ends at once, read `slurm-<jobid>.out`. The job checks that it can reach the LLM first.

## 7. Where runs write

AFL++ is 5–8x slower when it writes to the network home directory (2-minute tests on the same seeds):

| AFL++ output on | Tempest (EPYC, 2 CPUs) | Mac (M1, Docker) |
| --- | --- | --- |
| Campaign folder (network home / Mac shared folder) | 353 execs/s | 721 execs/s |
| Node-local disk (`/tmp`) | 2,741 execs/s | 3,665 execs/s |

So `scripts/fuzz run` puts `jhead_output/` on the node's local disk and copies it to `eval/<campaign>/` every 30 s,
at the end, and on `scancel` or the time limit. The local copy is deleted when the job ends.

G2Fuzz `pip install`s libraries the LLM asks for. Tempest limits the image's writable space to 64 MB,
so these go into `eval/<campaign>/.pyuser/` instead. Each campaign starts with only the image's packages, as in Docker.

## 8. Switching to Dr. Revelle's account

Nothing to change. Once `sacctmgr -nP show assoc user=$USER format=account` lists `group-mattrevelle`,
new runs and `llm start` use it (check with `scripts/fuzz account`). Jobs already queued or running keep their account.
If `G2F_ACCOUNT` is set in `~/.bashrc`, remove it, or it overrides this.

## 9. Results on the Mac

From the repo on the Mac (VPN on):

```bash
rsync -a tempest:BETTER-G2FUZZ/eval/<campaign> eval/
```

`scripts/fuzz results <campaign>` then works on the Mac too.
