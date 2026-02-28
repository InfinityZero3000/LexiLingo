#!/usr/bin/env python3
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path
import uuid


def load_env_file(env_path: Path) -> dict:
    env = {}
    if not env_path.exists():
        return env

    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip()
    return env


def http_json(method: str, url: str, payload: dict | None = None, timeout: float = 30.0):
    data = None
    headers = {"Content-Type": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read().decode("utf-8")
        return resp.status, json.loads(body) if body else {}


def fmt_sec(value: float) -> str:
    return f"{value:.2f}s"


def benchmark_ai_service(base_url: str, timeout: float = 90.0) -> tuple[bool, float, str, str]:
    """Run end-to-end benchmark via ai-service chat endpoints."""
    user_id = f"perf-user-{uuid.uuid4().hex[:8]}"
    title = "Qwen Perf Test"

    session_payload = {
        "user_id": user_id,
        "title": title,
    }
    session_url = f"{base_url.rstrip('/')}/api/v1/chat/sessions"

    status, session_data = http_json("POST", session_url, session_payload, timeout=15.0)
    if status != 200:
        return False, 0.0, "", f"create_session HTTP {status}"

    session_id = ((session_data or {}).get("data") or {}).get("session_id")
    if not session_id:
        return False, 0.0, "", "create_session returned no session_id"

    message_payload = {
        "user_id": user_id,
        "session_id": session_id,
        "message": "Give me one short English speaking tip.",
    }
    message_url = f"{base_url.rstrip('/')}/api/v1/chat/messages"

    start = time.perf_counter()
    status, message_data = http_json("POST", message_url, message_payload, timeout=timeout)
    elapsed = time.perf_counter() - start

    if status != 200:
        return False, elapsed, "", f"send_message HTTP {status}"

    data = (message_data or {}).get("data") or {}
    model_used = data.get("model_used", "unknown")
    response_text = data.get("ai_response", "")
    return True, elapsed, model_used, response_text


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    env_path = root / "ai-service" / ".env"
    env = load_env_file(env_path)

    base_url = os.getenv("OLLAMA_BASE_URL") or env.get("OLLAMA_BASE_URL", "http://localhost:11434")
    model = os.getenv("OLLAMA_MODEL") or env.get("OLLAMA_MODEL", "lexilingo-qwen3")
    timeout = float(os.getenv("OLLAMA_TIMEOUT") or env.get("OLLAMA_TIMEOUT", "30"))
    request_timeout = float(os.getenv("OLLAMA_REQUEST_TIMEOUT", "20"))
    run_chat_benchmark = os.getenv("QWEN_TEST_CHAT", "false").lower() == "true"
    run_e2e_benchmark = os.getenv("QWEN_TEST_E2E", "true").lower() == "true"
    ai_service_base = os.getenv("AI_SERVICE_BASE", "http://localhost:8001")
    e2e_timeout = float(os.getenv("QWEN_E2E_TIMEOUT", "90"))
    num_ctx = int(os.getenv("OLLAMA_CONTEXT_LENGTH") or env.get("OLLAMA_CONTEXT_LENGTH", "512"))
    num_predict = int(os.getenv("OLLAMA_MAX_TOKENS") or env.get("OLLAMA_MAX_TOKENS", "256"))

    print("=" * 64)
    print("QWEN OLLAMA TEST")
    print("=" * 64)
    print(f"Env file:      {env_path}")
    print(f"Ollama URL:    {base_url}")
    print(f"Model:         {model}")
    print(f"Timeout:       {timeout}s")
    print(f"Req timeout:   {request_timeout}s")
    print(f"Context:       {num_ctx}")
    print(f"Max tokens:    {num_predict}")
    print(f"Chat bench:    {run_chat_benchmark}")
    print(f"E2E bench:     {run_e2e_benchmark}")
    print(f"AI service:    {ai_service_base}")
    print("-" * 64)

    tags_url = f"{base_url.rstrip('/')}/api/tags"
    try:
        status, tags_data = http_json("GET", tags_url, timeout=10.0)
        if status != 200:
            print(f"❌ Ollama not healthy: HTTP {status}")
            return 2
    except urllib.error.URLError as exc:
        print(f"❌ Cannot connect to Ollama at {base_url}: {exc}")
        print("   Hãy chạy: ollama serve")
        return 2
    except Exception as exc:
        print(f"❌ Ollama health check failed: {exc}")
        return 2

    model_names = [m.get("name", "") for m in tags_data.get("models", [])]
    exact_match = any(name == model or name == f"{model}:latest" for name in model_names)
    fuzzy_match = any(model in name for name in model_names)

    print(f"✅ Ollama healthy. Installed models: {len(model_names)}")
    if not (exact_match or fuzzy_match):
        print(f"❌ Model '{model}' not found in Ollama")
        if model_names:
            print("   Installed:")
            for name in model_names[:10]:
                print(f"   - {name}")
        print(f"   Hãy chạy: ollama pull {model}")
        return 3

    chosen_model = model
    if exact_match:
        if f"{model}:latest" in model_names:
            chosen_model = f"{model}:latest"
    else:
        chosen_model = next(name for name in model_names if model in name)

    print(f"✅ Using model: {chosen_model}")

    generate_url = f"{base_url.rstrip('/')}/api/generate"
    probe_payload = {
        "model": chosen_model,
        "prompt": "Reply with exactly: OK",
        "stream": False,
        "options": {
            "temperature": 0.0,
            "num_ctx": min(num_ctx, 128),
            "num_predict": 1,
        },
    }

    print("🔎 Fast probe (/api/generate)...")
    probe_start = time.perf_counter()
    try:
        status, probe_data = http_json("POST", generate_url, probe_payload, timeout=request_timeout)
    except Exception as exc:
        print(f"❌ Probe failed: {exc}")
        return 4

    probe_elapsed = time.perf_counter() - probe_start
    if status != 200:
        print(f"❌ Probe returned HTTP {status}")
        print(json.dumps(probe_data, ensure_ascii=False, indent=2))
        return 4

    probe_text = (probe_data.get("response") or "").strip()
    print(f"✅ Probe latency: {fmt_sec(probe_elapsed)} | response: {probe_text[:60] or '(empty)'}")

    timings = [probe_elapsed]

    if run_chat_benchmark:
        chat_url = f"{base_url.rstrip('/')}/api/chat"
        payload = {
            "model": chosen_model,
            "messages": [
                {
                    "role": "system",
                    "content": "Answer in one short sentence under 12 words."
                },
                {
                    "role": "user",
                    "content": "Give one English speaking tip."
                }
            ],
            "stream": False,
            "options": {
                "temperature": 0.2,
                "num_ctx": min(num_ctx, 512),
                "num_predict": min(num_predict, 32)
            }
        }

        print("🔎 Chat benchmark (/api/chat)...")
        start = time.perf_counter()
        try:
            status, data = http_json("POST", chat_url, payload, timeout=request_timeout)
        except Exception as exc:
            print(f"❌ Chat benchmark failed: {exc}")
            return 4

        elapsed = time.perf_counter() - start
        timings.append(elapsed)

        if status != 200:
            print(f"❌ Chat benchmark returned HTTP {status}")
            print(json.dumps(data, ensure_ascii=False, indent=2))
            return 4

        content = (data.get("message") or {}).get("content") or data.get("response") or ""
        print(f"✅ Chat latency: {fmt_sec(elapsed)}")
        print("-" * 64)
        print("Sample chat response:")
        print((content or "(empty)")[:240])

    print("-" * 64)
    print(f"Probe latency:  {fmt_sec(timings[0])}")
    if len(timings) > 1:
        print(f"Chat latency:   {fmt_sec(timings[1])}")

    reference = timings[-1]
    if reference <= 3.0:
        print("🚀 Fast: response <= 3s")
    elif reference <= 6.0:
        print("🟡 Acceptable: response <= 6s")
    else:
        print("🔴 Slow: response > 6s")
        print("   Gợi ý: giảm OLLAMA_CONTEXT_LENGTH hoặc đổi model nhẹ hơn")

    if run_e2e_benchmark:
        print("-" * 64)
        print("🔎 End-to-end benchmark (ai-service API)...")
        try:
            ok, e2e_elapsed, model_used, response_text = benchmark_ai_service(
                ai_service_base,
                timeout=e2e_timeout,
            )
        except Exception as exc:
            print(f"❌ E2E benchmark failed: {exc}")
            return 5

        if not ok:
            print(f"❌ E2E benchmark failed: {response_text}")
            return 5

        print(f"✅ E2E latency: {fmt_sec(e2e_elapsed)}")
        print(f"✅ E2E model_used: {model_used}")
        print("Sample e2e response:")
        print((response_text or "(empty)")[:240])

    return 0


if __name__ == "__main__":
    sys.exit(main())
