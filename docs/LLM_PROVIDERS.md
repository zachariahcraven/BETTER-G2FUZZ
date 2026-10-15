# LLM Providers

The team uses **MSU CatChat** with `gpt-oss:120b` ([key guide](CATCHAT_API_KEY.md)).
This page covers the backups.

G2Fuzz works with any OpenAI-compatible server. Three `scripts/fuzz` variables pick the provider:

| Variable | Sets | Read by |
| --- | --- | --- |
| `G2F_KEY` | Key file | `run`, `shell` |
| `G2F_BASE_URL` | Server URL | `run`, `shell` |
| `G2F_MODEL` | Model, written to `model_setting.json` | `new`, `reuse` |

```bash
G2F_MODEL=qwen2.5-coder:7b scripts/fuzz new ollama1
G2F_KEY=~/.secrets/ollama.key G2F_BASE_URL=http://host.docker.internal:11434/v1 scripts/fuzz run ollama1
```

| Provider | Key | `OPENAI_BASE_URL` | Model | Use for |
| --- | --- | --- | --- | --- |
| **MSU CatChat** | [Free Key](CATCHAT_API_KEY.md) | `https://catchat-api.msu.montana.edu/v1` | `gpt-oss:120b` | Everything |
| GitHub Models | Fine-grained token, **Models: Read-only** | `https://models.github.ai/inference` | `openai/gpt-4.1-mini` | Dev only (daily limits) |
| Ollama (local) | Any text, e.g. `ollama` | `http://host.docker.internal:11434/v1` | `qwen2.5-coder:7b` | Unlimited fallback |
| OpenAI (paid) | OpenAI key | *(unset)* | `gpt-4.1-mini` | Upstream default |

Use one model for every configuration in an experiment.

## GitHub Models

1. Create a token at <https://github.com/settings/personal-access-tokens/new> with **Models: Read-only**.
2. Save it like the [CatChat key](CATCHAT_API_KEY.md#4-save-the-key), as `~/.secrets/github_models.key`.

## Ollama

Run it on the host so it can use the GPU.

```bash
brew install ollama
OLLAMA_CONTEXT_LENGTH=8192 ollama serve    # leave running; the default context truncates prompts
ollama pull qwen2.5-coder:7b               # in another terminal
echo ollama > ~/.secrets/ollama.key
```

If the container can't connect, restart with `OLLAMA_HOST=0.0.0.0`.
On a 16 GB Mac, use a 7B model and give Colima about 8 GB.

## Request volume

Each LLM step made 3–13 requests in testing. A 24 h campaign makes about 140–600.
CatChat has no rate limit. Daily-capped free tiers can't support full experiments.
