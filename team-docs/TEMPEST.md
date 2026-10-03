# Running on Tempest

Tempest is MSU's HPC cluster. `scripts/fuzz` works the same there.
Without Docker, it runs each campaign as a Slurm job in an Apptainer image.
Official docs: [Tempest](https://www.montana.edu/uit/rci/tempest).

## 1. Check your Slurm accounts

Log in with `ssh <netid>@tempest-login.msu.montana.edu` (VPN off campus), or use the web shell at
<https://tempest-web.msu.montana.edu> (Clusters → Tempest Login Shell Access).

```bash
sacctmgr -nP show assoc user=$USER format=account
```

| Account | Partitions |
| --- | --- |
| `group-<name>` | `fairshare`, `unsafe` (preemptible) |
| `priority-<name>` | `priority`, `interactive` |

Dr. Revelle's accounts are `group-mattrevelle` and `priority-mattrevelle`. Ask him to add you.

## 2. Get the code and a key

```bash
git clone https://github.com/zachariahcraven/BETTER-G2FUZZ.git && cd BETTER-G2FUZZ
mkdir -p -m 700 ~/.secrets
cat > ~/.secrets/catchat.key        # paste the key, then Ctrl-D
chmod 600 ~/.secrets/catchat.key
```

Make a separate key for Tempest ([CATCHAT_API_KEY.md](CATCHAT_API_KEY.md)).

## 3. Settings

Add to `~/.bashrc`, then log in again:

```bash
export G2F_ACCOUNT=group-mattrevelle
export G2F_PARTITION=fairshare
```

`G2F_CPUS` (default 2) and `G2F_MEM` (default 4G) set each job's size.

## 4. Get the image

Tempest can't build Docker images. Rootless Podman doesn't work on its home file system.
Build an x86_64 image on your Mac, then convert it on Tempest. One person does this and shares `g2fuzz.sif`.

On the Mac, one time:

```bash
brew install docker-buildx
mkdir -p ~/.docker/cli-plugins && ln -sf "$(brew --prefix)/bin/docker-buildx" ~/.docker/cli-plugins/
colima stop && colima start --vz-rosetta        # Rosetta makes x86_64 builds fast
```

Each build:

```bash
docker buildx build --platform linux/amd64 -f docker/Dockerfile.g2fuzz -t g2fuzz:amd64 --load .
docker save g2fuzz:amd64 | gzip -1 | ssh <netid>@tempest-login.msu.montana.edu 'cat > BETTER-G2FUZZ/g2fuzz-amd64.tar.gz'
```

On Tempest:

```bash
gunzip g2fuzz-amd64.tar.gz
srun -A $G2F_ACCOUNT -p $G2F_PARTITION -c 4 --mem 8G -t 60 \
  apptainer build g2fuzz.sif docker-archive:g2fuzz-amd64.tar && rm g2fuzz-amd64.tar
```

Rebuild after changing the code, as on the Mac.

## 5. First campaign

```bash
scripts/fuzz new first
scripts/fuzz run first 900 --test
scripts/fuzz watch first
```

Everything in [WORKFLOW.md](../WORKFLOW.md) works. These commands differ:

| Command | On Tempest |
| --- | --- |
| `run` | Submits a Slurm job. `eval/<campaign>/` gets `job.sbatch` and the log `slurm-<jobid>.out` |
| `shell` | Interactive Slurm job (4 h) with `apptainer shell` |
| `stop` | `scancel` |
| `watch`, `status`, `list` | Show the job state from `squeue`. Run them on the login node |

If a job ends at once, read `slurm-<jobid>.out`. The job checks that it can reach CatChat first.
