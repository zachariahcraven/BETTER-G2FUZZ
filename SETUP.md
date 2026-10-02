# Setup: Build the Image and Run G2Fuzz

Everything runs inside Docker. Run commands from the repo root unless a step says otherwise.

> **Note:** Steps 1–8 are tested on an arm64 Mac, including the `llmGen-M` step.

## 1. Prerequisites (one time)

**Docker**
- macOS: `brew install docker colima`, then `colima start --cpu 4 --memory 8 --disk 60`
- Linux: Docker Engine
- Windows: Docker Desktop with WSL2

**CatChat API key.** Follow [team-docs/CATCHAT_API_KEY.md](team-docs/CATCHAT_API_KEY.md).
The key goes in `~/.secrets/catchat.key`. Never put it in the repo.

Backup providers (GitHub Models, Ollama): [team-docs/LLM_PROVIDERS.md](team-docs/LLM_PROVIDERS.md).

## 2. Build the image (one time, 15–30 min)

```bash
docker build -f docker/Dockerfile.g2fuzz -t g2fuzz:dev .
```

Rebuild after changes to `src/`, `include/` or the Python files.

## 3. Create a campaign folder

```bash
mkdir -p eval/jhead-run1
cp program_to_format.json eval/jhead-run1/
echo '{"model": ["gpt-oss:120b"]}' > eval/jhead-run1/model_setting.json
```

`eval/` is ignored by git.

## 4. Start a container

```bash
docker run --rm -it \
  -v "$PWD/eval/jhead-run1:/eval" \
  -v "$HOME/.secrets/catchat.key:/eval/openai_key.txt:ro" \
  -e OPENAI_BASE_URL=https://catchat-api.msu.montana.edu/v1 \
  g2fuzz:dev
```

You start in `/eval`. **Run steps 6–7 from `/eval`.**
G2Fuzz reads `openai_key.txt`, `model_setting.json` and `program_to_format.json` from the current directory.

## 5. Targets (prebuilt)

The image includes instrumented targets in `/targets/`. Nothing to build.

| Target | Normal build | CmpLog build | Input |
| --- | --- | --- | --- |
| jhead | `/targets/jhead.afl` | `/targets/jhead.cmp` | JPEG |

New targets are added in `docker/Dockerfile.g2fuzz`.

## 6. Generate seeds with the LLM

```bash
mkdir -p initial_seeds
cp /AFLplusplus/testcases/images/jpeg/*.jpg initial_seeds/
python /AFLplusplus/program_gen.py --output ./jhead_output --program jhead
cp jhead_output/default/gen_seeds/* initial_seeds/
```

`--program` must be a key in `program_to_format.json`.

## 7. Fuzz

```bash
afl-fuzz -i initial_seeds -o jhead_output -c /targets/jhead.cmp -m 1024 -k /AFLplusplus/ -- /targets/jhead.afl @@
```

- Always pass `-k /AFLplusplus/`.
- Add `-V 3600` to stop after an hour.
- After 5+ minutes without new coverage, the stage shows `llmGen-M` while the LLM writes a generator.
  Fuzzing pauses until the LLM step finishes.
- **Testing only:** add `-e G2F_PLATEAU_SEC=10 -e G2F_BACKOFF_SEC=0` to `docker run` to trigger
  `llmGen-M` after 10 s without finds. Leave these unset for real experiments.

## 8. Results

Output is in `eval/jhead-run1/jhead_output/default/` and stays after the container exits.

| Path | Contents |
| --- | --- |
| `queue/` | Corpus. `orig:jpg-N_k` entries came from G2Fuzz generators |
| `crashes/` | Crashing inputs |
| `generators/` | Python generators the LLM wrote |
| `fuzzer_stats`, `plot_data` | Coverage and speed (`afl-plot` graphs these) |
| `mutate_log` | Output of each LLM step |
| `mutation_log/relationship.json` | Which generator was mutated into which |
| `gen_seeds_energy_log` | Seeds added and time spent in the LLM |
| `/eval/llm_calls.jsonl` | One line per LLM request: latency, success or error, retry attempt |

## Common problems

| Problem | Fix |
| --- | --- |
| `Cannot connect to the Docker daemon` | Start Docker (`colima start` on macOS) |
| `FileNotFoundError: model_setting.json` or `openai_key.txt` | Not in `/eval`, or the key mount is missing |
| `openai.AuthenticationError` | Key file is wrong, expired, or doesn't match `OPENAI_BASE_URL` |
| `openai.NotFoundError` / unknown model | Use an exact model ID (`gpt-oss:120b`) |
| LLM requests time out off campus | Connect to the MSU VPN |
| `llmGen-M` never shows up | Normal at first. It needs 5+ minutes without new coverage (or set `G2F_PLATEAU_SEC` when testing) |
| Fuzzing stalls for minutes | An `llmGen-M` step is waiting on a slow LLM. Check `llm_calls.jsonl` for timeouts |
| Generators install odd pip packages | Expected. This is why everything runs in Docker |
