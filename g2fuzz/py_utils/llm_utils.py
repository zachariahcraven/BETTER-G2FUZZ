from openai import OpenAI
import os
import json
import time

with open('openai_key.txt', 'r') as file:
    key = file.read().strip()

OPENAI_KEY = key

# G2F: one client with a per-call timeout and the SDK's own retries (connection errors, 408/409/429/5xx,
# exponential backoff), so a transient server error doesn't crash seed generation. Upstream sets neither
# (SDK defaults: 600 s, 2 retries). One JSON line per call goes to llm_calls.jsonl for scripts/fuzz and the analysis.
LLM_TIMEOUT = float(os.environ.get("G2F_LLM_TIMEOUT", 300))
LLM_RETRIES = int(os.environ.get("G2F_LLM_RETRIES", 5))
LLM_LOG = os.environ.get("G2F_LLM_LOG", "llm_calls.jsonl")

client = OpenAI(api_key=OPENAI_KEY, timeout=LLM_TIMEOUT, max_retries=LLM_RETRIES)

def llm_messages(model, messages, temperature):
    start = time.time()
    status = "ok"
    try:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature
        )
        return response.choices[0].message.content
    except Exception as e:
        status = type(e).__name__
        raise
    finally:
        try:
            with open(LLM_LOG, 'a') as f:
                f.write(json.dumps({"ts": round(start, 3), "model": model,
                                    "secs": round(time.time() - start, 2), "status": status}) + "\n")
        except OSError:
            pass

def llm(model, prompt, temperature):
    return llm_messages(model, [{"role": "user", "content": prompt}], temperature)

if __name__ == "__main__":
    prompt = """
    hi
    """
    print(llm("gpt-4o-mini-2024-07-18", prompt, 0.7))
