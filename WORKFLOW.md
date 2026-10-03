# Workflow

Day-to-day use after [SETUP.md](SETUP.md) or [TEMPEST.md](team-docs/TEMPEST.md). Run commands from the repo root.

## Commands

`scripts/fuzz help` shows this list.

| Command | Does |
| --- | --- |
| `new [name]` | Create a campaign folder (default name `jhead-MMDD-HHMM`) |
| `reuse <from> [name]` | New campaign with seeds and generators from `eval/<from>`. Skips seed generation (15–20 min) |
| `run <name> [secs]` | Background run: seed generation if needed, then fuzz (default 3600 s) |
| `shell <name>` | Interactive shell in the image, in that campaign |
| `watch <name>` | Live view, updated every second (the run's numbers reach `eval/` every 30 s) |
| `status [name]` | One campaign's numbers once. No name: same as `list` |
| `results <name>` | Final summary |
| `stop <name>` | Stop the run. Files stay |
| `list` | All campaigns |

- `--test` on `run` or `shell` fires `llmGen-M` after 10 s without new coverage. Never use it for experiments.
- Environment variables change the key, server, model, target and image. See `scripts/fuzz help`.
- To share seeds, copy `initial_seeds/` and `jhead_output/default/generators/` into a teammate's `eval/<campaign>/`.
- On Linux, campaign files are owned by root (the container runs as root). Delete them with `sudo`.

## Alias and tab completion (zsh)

Run once from the repo root:

```bash
printf '%s\n' "alias fuzz='$PWD/scripts/fuzz'" "source '$PWD/scripts/fuzz-completion.zsh'" >> ~/.zshrc && source ~/.zshrc
```

## Manual commands

For anything the script doesn't cover, run `scripts/fuzz shell <campaign>`. Inside, from `/eval`:

```bash
# Seed generation. Skip if the campaign already has initial_seeds/.
python /AFLplusplus/program_gen.py --output ./jhead_output --program jhead
mkdir -p initial_seeds && cp /AFLplusplus/testcases/images/jpeg/* jhead_output/default/gen_seeds/* initial_seeds/

# Fuzz with the AFL++ screen
afl-fuzz -i initial_seeds -o jhead_output -c /targets/jhead.cmp -m 1024 -V 3600 -k /AFLplusplus/ -- /targets/jhead.afl @@
```

- Always pass `-k /AFLplusplus/`.
- `-o` in `/eval` is 5–8x slower (shared folder or network disk). For speed, use `-o /tmp/jhead_output` and copy it to `/eval` at the end. `scripts/fuzz run` does this for you.
- `--program` must be a key in `program_to_format.json`.
- Targets are prebuilt as `/targets/<name>.afl` and `.cmp`. Add new ones in `docker/Dockerfile.g2fuzz`.

## Change the code

Rebuild the image after any change ([SETUP step 4](SETUP.md#4-build-the-image), 5–10 min), then start a new campaign.

| What | File |
| --- | --- |
| Generator and mutator selection (scheduler hook) | `generator_mutation.py` |
| Seed generation | `program_gen.py` |
| LLM calls, retries, logging | `py_utils/llm_utils.py` |
| When `llmGen-M` triggers | `src/afl-fuzz.c` (search `G2F:`) |
| Image contents and targets | `docker/Dockerfile.g2fuzz` |

## Git

- Branch off `dev`. `main` is the untouched upstream.
- `eval/` and keys are git-ignored. Don't force-add them.
