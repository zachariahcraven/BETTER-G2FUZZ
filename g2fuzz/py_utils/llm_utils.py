from openai import OpenAI, APIConnectionError, APITimeoutError, InternalServerError, RateLimitError
import os
import json
import time

with open('openai_key.txt', 'r') as file:
    key = file.read().strip()

OPENAI_KEY = key

# G2F: one shared client with a longer timeout, plus retries with backoff, so a transient
# server error (e.g. CatChat "stream timeout") doesn't crash seed generation.
LLM_TIMEOUT = float(os.environ.get("G2F_LLM_TIMEOUT", 300))
LLM_ATTEMPTS = int(os.environ.get("G2F_LLM_RETRIES", 6))
LLM_LOG = os.environ.get("G2F_LLM_LOG", "llm_calls.jsonl")
RETRYABLE = (APIConnectionError, APITimeoutError, InternalServerError, RateLimitError)

client = OpenAI(api_key=OPENAI_KEY, timeout=LLM_TIMEOUT, max_retries=0)

def log_call(model, start, status, attempt):
    """Append one line per LLM request: timestamp, model, latency, outcome."""
    try:
        with open(LLM_LOG, 'a') as f:
            f.write(json.dumps({"ts": round(start, 3), "model": model, "secs": round(time.time() - start, 2),
                                "status": status, "attempt": attempt}) + "\n")
    except OSError:
        pass

def chat(model, messages, temperature):
    for attempt in range(1, LLM_ATTEMPTS + 1):
        start = time.time()
        try:
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature
            )
            log_call(model, start, "ok", attempt)
            return response.choices[0].message.content
        except RETRYABLE as e:
            log_call(model, start, type(e).__name__, attempt)
            if attempt == LLM_ATTEMPTS:
                raise
            wait = min(2 ** attempt, 60)
            print(f"LLM {type(e).__name__} (attempt {attempt}/{LLM_ATTEMPTS}), retrying in {wait}s")
            time.sleep(wait)

def llm(model, prompt, temperature):
    return chat(model, [{"role": "user", "content": prompt}], temperature)

def llm_messages(model, messages, temperature):
    return chat(model, messages, temperature)

if __name__ == "__main__":
    prompt = """
    hi
    """
    print(llm("gpt-4o-mini-2024-07-18", prompt, 0.7))
