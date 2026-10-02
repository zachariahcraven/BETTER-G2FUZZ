# LLM Providers

The team uses **MSU CatChat** with `gpt-oss:120b` ([key guide](CATCHAT_API_KEY.md)).
This page covers the backups.

G2Fuzz works with any OpenAI-compatible server. Three settings pick the provider:

| Setting | Where it goes |
| --- | --- |
| API key | `~/.secrets/<provider>.key`, mounted as `/eval/openai_key.txt` |
| Server URL | `-e OPENAI_BASE_URL=...` on `docker run` |
| Model | `model_setting.json` in the campaign folder |

| Provider | Key | `OPENAI_BASE_URL` | Model | Use for |
| --- | --- | --- | --- | --- |
| **MSU CatChat** | [Free Key](CATCHAT_API_KEY.md) | `https://catchat-api.msu.montana.edu/v1` | `gpt-oss:120b` | Everything |
| GitHub Models | Fine-grained token, **Models: Read-only** | `https://models.github.ai/inference` | `openai/gpt-4.1-mini` | Dev only (daily limits) |
| Ollama (local) | Any text, e.g. `ollama` | `http://host.docker.internal:11434/v1` | `qwen2.5-coder:7b` | Unlimited fallback |
| OpenAI (paid) | OpenAI key | *(unset)* | `gpt-4.1-mini` | Upstream default |

Use one model for every configuration in an experiment.

## GitHub Models

1. Create a token at <https://github.com/settings/personal-access-tokens/new> with **Models: Read-only**.
2. `pbpaste > ~/.secrets/github_models.key && chmod 600 ~/.secrets/github_models.key`

## Ollama

Run it on the host so it can use the GPU.

```bash
brew install ollama
OLLAMA_CONTEXT_LENGTH=8192 ollama serve    # leave running
ollama pull qwen2.5-coder:7b               # in another terminal
echo ollama > ~/.secrets/ollama.key
```

The default context is too small and silently truncates G2Fuzz prompts.
Add `--add-host=host.docker.internal:host-gateway` to `docker run`.
If the container can't connect, restart with `OLLAMA_HOST=0.0.0.0`.
On a 16 GB Mac, use a 7B model and give Colima about 8 GB.

## Request volume

Each LLM step makes up to about 8 requests. A 24 h campaign makes roughly 300–500.
Daily-capped free tiers can't support full experiments.
