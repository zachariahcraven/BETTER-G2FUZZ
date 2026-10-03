# Setup: First Run

One-time setup, then a short test campaign. Run commands from the repo root.
Tested on an arm64 Mac. For Tempest, follow [team-docs/TEMPEST.md](team-docs/TEMPEST.md) instead.

## 1. Install Docker

| OS | Install |
| --- | --- |
| macOS | `brew install docker colima`, then `colima start --cpu 4 --memory 8 --disk 60` |
| Linux | Docker Engine |
| Windows | Docker Desktop with WSL2. Clone the repo and run every command inside WSL |

Docker needs about 8 GB of RAM.
On macOS, run `colima start` after each reboot and `colima stop` when you're done.

## 2. Get the code

```bash
git clone https://github.com/zachariahcraven/BETTER-G2FUZZ.git
cd BETTER-G2FUZZ
```

## 3. Get a CatChat key

Follow [team-docs/CATCHAT_API_KEY.md](team-docs/CATCHAT_API_KEY.md). The key goes in `~/.secrets/catchat.key`.
Off campus, connect to the MSU VPN.

## 4. Build the image

```bash
docker build -f docker/Dockerfile.g2fuzz -t g2fuzz:dev .
```

The first build takes 15–30 min. Rebuild after changing `src/`, `include/` or the Python files.

## 5. First campaign

```bash
scripts/fuzz new first
scripts/fuzz run first 900 --test
scripts/fuzz watch first
```

- Seed generation runs first (15–20 min). Then fuzzing runs for 900 s.
- `--test` fires the LLM step (`llmGen-M`) after 10 s without new coverage, so you see one. Never use it for experiments.
- Ctrl-C closes `watch`. The run keeps going.
- When it finishes: `scripts/fuzz results first`.

Day-to-day commands are in [WORKFLOW.md](WORKFLOW.md).

## 6. Output files

Everything is in `eval/<campaign>/` and stays after the container exits.

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

## Common problems

| Problem | Fix |
| --- | --- |
| `Docker isn't running` | `colima start` (macOS) |
| `image g2fuzz:dev not found` | Build it (step 4) |
| `API key missing or empty` | Save the key (step 3) |
| `watch` says seed generation stopped or failed | Check the key and VPN, read `seedgen.log`, then `run` again |
| `openai.AuthenticationError` in a log | The key is wrong or expired |
| `openai.NotFoundError` / unknown model | Use the exact model ID `gpt-oss:120b` |
| LLM requests time out | Off campus: use the VPN. CatChat is slowest midday |
| `llmGen-M` never shows up | Normal. It needs 5+ min without new coverage (or `--test`) |
| Fuzzing stalls for minutes | An LLM step is waiting on CatChat. `watch` shows the phase |
| Generators install odd pip packages | Expected. This is why everything runs in Docker |
