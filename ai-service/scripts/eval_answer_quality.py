"""Does the better prompt make Lexi's reply better?

Usage:  redis-server --port 6379 --save "" &          # the key pool needs it
        python scripts/eval_answer_quality.py <copy-of-kuzu_runtime.db> [N]

Kuzu locks the file, so point this at a COPY, never at the database a running
ai-service has open. Writes answer_eval.json next to it, after every case, so a
run killed halfway still yields its completed pairs.

Same pipeline, same diagnosis, same generator, same decoding — the only
difference is the retrieved context: tier-1 topic routing on vs off. Replies
are compared blind and in both orders so a position-biased judge cancels out.

Three things this harness has to get right or it measures nothing:
  * provider keys come from ai-service/.env, else generate_node answers
    "Squawk! I'm temporarily unable to reach my language model" for both arms
  * the Groq key pool needs a real Redis; without it get_available_groq_key
    round-robins blind and half the generations die on 429
  * generate_node falls back to a local 1.7B Ollama model, which would compare
    a 27B reply against a 1.7B one; that fallback is pointed at a dead port and
    any case whose two arms did not use the same generator is discarded
"""
import asyncio, json, os, sys, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from dotenv import load_dotenv
load_dotenv(os.path.join(ROOT, ".env"), override=False)

os.environ["KUZU_DB_PATH"] = sys.argv[1]
os.environ["LEARNER_STATE_MODE"] = "read"          # as production runs it
os.environ["V3_ENABLE_GRAPH_ANALYTICS"] = "true"
os.environ["GROQ_MODEL"] = "qwen/qwen3.6-27b"      # prod model, not the local .env one
os.environ["TRACECAG_LLM_MAX_RETRIES"] = "2"
os.environ["OLLAMA_BASE_URL"] = "http://127.0.0.1:1"   # no silent 1.7B replies
N = int(sys.argv[2]) if len(sys.argv) > 2 else 60
EXPECTED_GEN = "groq/qwen/qwen3.6-27b"
OLLAMA = "http://localhost:11434/api/chat"
JUDGE_LOCAL = "llama3.1:8b"

import logging; logging.disable(logging.WARNING)
import httpx
import redis.asyncio as _redis
from api.core.groq_key_pool import build_groq_key_pool, get_available_groq_key
import api.services.retrieval_service_v3 as V3
import api.services.trace_cag.retrieve as R
import api.services.trace_cag.generate as G
from api.services.trace_cag.nodes_v2 import kg_expand_node
from api.services.trace_cag.llm_client import _throttled_post_json
from api.services.trace_cag.provider_state import _PROVIDER_DISABLED_UNTIL

class _NoL2:
    async def query_l2(self, q): return []
R.get_doc_intel_service = lambda: _NoL2()

TOPICS = json.load(open(os.path.join(ROOT, "data/eval/topic_paraphrases.json")))
CASES = [(t["queries"][0], t["topic_id"], t["level"]) for t in TOPICS][:N]

JUDGE = """You are grading an English tutoring chatbot for language learners.

The learner said:
{q}

Two tutor replies:

[A]
{a}

[B]
{b}

Which reply is better for this learner? Judge on, in order of importance:
1. Does it engage with what the learner actually asked, with concrete material
   (specific phrases, vocabulary, a scenario they can practise)?
2. Is it usable right now for practice, rather than generic encouragement?
3. Is it appropriate for their level and free of invented or off-topic content?

Reply with JSON only: {{"winner": "A" or "B" or "tie", "why": "<one short sentence>"}}"""


async def judge_groq(prompt):
    key = await get_available_groq_key(estimated_tokens=500)
    if not key:
        return None
    resp = await _throttled_post_json(
        provider="groq",
        url="https://api.groq.com/openai/v1/chat/completions",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        payload={"model": "qwen/qwen3.6-27b",
                 "messages": [{"role": "user", "content": prompt}],
                 "response_format": {"type": "json_object"},
                 "temperature": 0.0, "max_tokens": 200},
        timeout=60.0,
    )
    if resp is None or resp.status_code != 200:
        return None
    return json.loads(resp.json()["choices"][0]["message"]["content"])


async def judge_local(prompt):
    async with httpx.AsyncClient(timeout=600.0) as c:
        r = await c.post(OLLAMA, json={
            "model": JUDGE_LOCAL, "stream": False, "format": "json",
            "keep_alive": "60m",
            "options": {"temperature": 0, "num_predict": 90, "num_ctx": 3072},
            "messages": [{"role": "user", "content": prompt}],
        })
    r.raise_for_status()
    return json.loads(r.json()["message"]["content"])


async def judge(q, a, b):
    """Groq only, with one retry.

    A local llama3.1:8b fallback was tried and removed: 202s per call on this
    CPU-only box, and while it ran it took every core, so the harness sat at 0%
    waiting and even RetrievalServiceV3 construction went 175s -> 535s. A case
    whose judgement fails is dropped, which is symmetric across both arms."""
    prompt = JUDGE.format(q=q, a=a, b=b)
    for attempt in (1, 2):
        try:
            out = await asyncio.wait_for(judge_groq(prompt), timeout=90)
            if out and out.get("winner") in {"A", "B", "tie"}:
                return out["winner"], "groq", out.get("why", "")
        except Exception as exc:
            print(f"[judge {type(exc).__name__}]", end="", flush=True)
        if attempt == 1:
            await asyncio.sleep(8)
    return None, None, ""


async def one_arm(q, level, routing_on):
    V3._TOPIC_ROUTE_MIN_SIM = 0.40 if routing_on else 9.9
    state = {
        "user_input": q, "session_id": f"ans-{routing_on}", "user_id": "eval-user",
        "retrieval_policy": "rapid", "learner_profile": {"level": level},
        "conversation_history": [], "cache_policy": "off", "generation_policy": "auto",
    }
    state.update(await kg_expand_node(state))
    state.update({"diagnosis_root_causes": [], "diagnosis_errors": [],
                  "diagnosis_confidence": 0.9, "diagnosis_intent": "practice",
                  "fluency_score": 0.8, "grammar_score": 0.8})
    state.update(await R.retrieve_node(state))
    out = await G.generate_node(state)
    return {"reply": str(out.get("tutor_response") or ""),
            "model": (out.get("models_used") or ["?"])[0],
            "context": state.get("retrieved_context", ""),
            "routed": state["retrieval_meta"]["topic_routing"]["routed"]}


async def both_arms(q, level):
    # Groq's free tier is ~8,000 tokens per minute per key and a grounded
    # generation request is ~2,000 of them, so two arms back to back on one key
    # trip a 429 whose body disables that key in-process for 300s. Spacing the
    # calls keeps every key under its own per-minute budget; clearing the
    # disable map stops one early 429 from poisoning the rest of the run, since
    # a direct probe shows all seven keys healthy with ~999 requests left.
    _PROVIDER_DISABLED_UNTIL.clear()
    off = await asyncio.wait_for(one_arm(q, level, False), timeout=150)
    await asyncio.sleep(8)
    on = await asyncio.wait_for(one_arm(q, level, True), timeout=150)
    await asyncio.sleep(8)
    return off, on


async def main():
    rc = _redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    await rc.ping()
    pool = build_groq_key_pool(rc)
    print(f"groq key pool: {pool.count if pool else 0} keys", flush=True)
    t = time.time(); await R._get_retrieval_v3(); print(f"V3 built {time.time()-t:.0f}s", flush=True)

    rows = []
    for i, (q, topic, level) in enumerate(CASES):
        try:
            off, on = await both_arms(q, level)
            if off["model"] != EXPECTED_GEN or on["model"] != EXPECTED_GEN:
                await asyncio.sleep(20)
                off, on = await both_arms(q, level)
        except asyncio.TimeoutError:
            print(f"[{i}:gen-timeout]", end="", flush=True); continue
        if off["model"] != EXPECTED_GEN or on["model"] != EXPECTED_GEN:
            print(f"[{i}:gen-{off['model']}/{on['model']}]", end="", flush=True)
            rows.append({"q": q, "topic": topic, "off": off, "on": on, "verdicts": [], "judges": []})
            continue
        w1, j1, why1 = await judge(q, off["reply"], on["reply"])   # A=off B=on
        w2, j2, why2 = await judge(q, on["reply"], off["reply"])   # A=on  B=off
        verdicts = []
        if w1: verdicts.append({"A": "off", "B": "on", "tie": "tie"}[w1])
        if w2: verdicts.append({"A": "on", "B": "off", "tie": "tie"}[w2])
        rows.append({"q": q, "topic": topic, "off": off, "on": on,
                     "verdicts": verdicts, "judges": [j1, j2], "why": [why1, why2]})
        print(f"{i}.", end="", flush=True)
        json.dump(rows, open(os.path.join(os.path.dirname(sys.argv[1]), "answer_eval.json"), "w"))
        await asyncio.sleep(4)
    print()
    json.dump(rows, open(os.path.join(os.path.dirname(sys.argv[1]), "answer_eval.json"), "w"))
    report(rows)


def report(rows):
    ok = [r for r in rows if r["off"]["model"] == r["on"]["model"] == EXPECTED_GEN]
    scored = [r for r in ok if len(r["verdicts"]) == 2]
    print(f"\ncases run {len(rows)}   same generator both arms {len(ok)}   "
          f"judged in both orders {len(scored)}")
    if not scored:
        print("nothing judged — check the Retry-After values in the log; a 220-372s "
              "backoff means the daily token budget is gone, not the per-minute one")
        return
    won = sum(1 for r in scored if r["verdicts"] == ["on", "on"])
    lost = sum(1 for r in scored if r["verdicts"] == ["off", "off"])
    print(f"\n  routing ON  wins (both orders) : {won:3d}  ({100*won/len(scored):.1f}%)")
    print(f"  routing OFF wins (both orders) : {lost:3d}  ({100*lost/len(scored):.1f}%)")
    print(f"  tie / judge inconsistent       : {len(scored)-won-lost:3d}")
    print(f"\n  avg reply chars   off {sum(len(r['off']['reply']) for r in ok)//len(ok)}"
          f"   on {sum(len(r['on']['reply']) for r in ok)//len(ok)}")
    print(f"  avg context chars off {sum(len(r['off']['context']) for r in ok)//len(ok)}"
          f"   on {sum(len(r['on']['context']) for r in ok)//len(ok)}")
    print(f"  turns routed      {sum(1 for r in rows if r['on']['routed'])}/{len(rows)}")


if __name__ == "__main__":
    asyncio.run(main())
