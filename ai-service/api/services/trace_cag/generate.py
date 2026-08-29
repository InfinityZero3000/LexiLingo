"""
TraceCAG generate_node — grounded generation (LLM call with KG/retrieval context).

Split out of nodes_v2.py (Phase 4 refactor) along with its prompt-building and
token-streaming helpers, which the streaming chat endpoint also calls directly.
"""

import asyncio
import json
import logging
import os
import time
from collections import Counter
from typing import Any, AsyncGenerator, Dict, List

from api.services.trace_cag.state import TraceCAGState
from api.services.trace_cag.evaluation_agent import EvaluationAgent
from api.services.document_intelligence import get_doc_intel_service
from api.services.llama_kv_service import get_local_llama_kv_service

from api.services.trace_cag.env_helpers import _env_flag
from api.services.trace_cag.provider_state import _provider_is_disabled
from api.services.trace_cag.llm_client import (
    _get_httpx_client,
    _qwen_no_think_messages,
    _qwen_reasoning_overrides,
    _throttled_post_json,
)
from api.services.trace_cag.cache_utils import _write_cache_entry
from api.services.trace_cag.dependencies import POLICY_VERSION_TOKEN, dependency_record

from api.services.trace_cag.benchmark.ranking import _update_ranker_from_generation
from api.services.trace_cag.benchmark.qa_generation import (
    _generate_extractive_fallback_response,
    _generate_benchmark_qa_response,
)

logger = logging.getLogger(__name__)

SAFE_TUTOR_FALLBACK = (
    "Squawk! I'm temporarily unable to reach my language model. "
    "Please try again in a moment."
)


class ProviderBusyError(RuntimeError):
    pass


def _state_with_policy_dependency(state: TraceCAGState) -> TraceCAGState:
    return {
        **state,
        "dependency_events": [
            *(state.get("dependency_events") or []),
            dependency_record("policy:tracecag:generation", "policy", POLICY_VERSION_TOKEN, "generation-policy"),
        ],
    }

_LOCAL_LLAMA_CORE_SYSTEM_PROMPT = (
    "You are Lexi, an expert English tutor. "
    "Provide grounded, concise and actionable feedback. "
    "If evidence is weak, state uncertainty explicitly."
)


def _personalization_hint(state: Dict[str, Any]) -> str:
    learner_profile = state.get("learner_profile") or {}
    # Authoritative facts about the learner themselves (name, level, XP,
    # enrolled courses), injected only on turns that ask about them — see
    # api.services.learner_card. Goes first so the model treats it as ground
    # truth rather than as one more stylistic hint.
    hint = str(learner_profile.get("learner_facts") or "").strip()
    if hint:
        hint += "\n"
    goal = str(learner_profile.get("goal") or "").strip()
    interest = str(learner_profile.get("interest") or "").strip()
    if goal or interest:
        if goal and interest:
            who = f"is learning for {goal} and is into {interest}"
        else:
            who = f"is learning for {goal}" if goal else f"is into {interest}"
        hint += f"The learner {who} — use examples from that when it fits naturally.\n"

    recap = str(learner_profile.get("session_recap") or "").strip()
    if recap:
        hint += (
            f'This is the learner\'s first message in a new conversation. Last '
            f'time, they said: "{recap}" — if it feels natural, briefly '
            f"acknowledge picking back up; don't force it if this message is "
            f"on a completely different topic.\n"
        )

    # Durable (Postgres learner_concept_states, no TTL) signal takes priority
    # over the Redis rolling cache: does the concept THIS turn's diagnosis
    # just touched also have a persistent track record of low mastery across
    # ALL past sessions? Populated by _load_learner_concept_overlay — empty
    # whenever LEARNER_STATE_MODE is "off", so this safely no-ops until the
    # feature is enabled.
    concept_states = state.get("learner_concept_states") or {}
    root_causes = state.get("diagnosis_root_causes") or []
    struggling_concept = None
    for concept_id in root_causes:
        info = concept_states.get(str(concept_id))
        if not isinstance(info, dict):
            continue
        error_count = int(info.get("error_count") or 0)
        mastery = info.get("mastery_probability")
        mastery = float(mastery) if mastery is not None else 1.0
        if error_count >= 2 and mastery < 0.55:
            struggling_concept = str(concept_id)
            break

    if struggling_concept:
        readable = (
            struggling_concept.split(":")[-1].replace(".", " ").replace("_", " ").strip()
        )
        if readable:
            hint += (
                f"This learner has a persistent track record of struggling with "
                f"'{readable}' across past sessions, and just made a related error "
                "again. If a natural opportunity comes up, reinforce it gently with "
                "a short example — don't call it out as a repeated failure.\n"
            )
    else:
        # Fallback: Redis rolling cache (last ~20 diagnosed errors, 7-day
        # window — see LearnerProfileCache). Less precise (not tied to this
        # turn's concept) but still useful when the durable store has no
        # opinion yet (feature just enabled, or this concept never recorded).
        common_errors = learner_profile.get("common_errors") or []
        if common_errors:
            top_error, _count = Counter(common_errors).most_common(1)[0]
            readable = top_error.replace("_", " ").strip()
            if readable:
                hint += (
                    f"This learner has repeatedly struggled with '{readable}' across "
                    "recent turns. If a natural opportunity comes up in this reply, "
                    "gently reinforce it with a short example — don't call it out as "
                    "a repeated failure or force it into an unrelated message.\n"
                )
    return hint


def _build_base_system_prompt(state: Dict[str, Any], level: str, difficulty: str) -> str:
    topic_prompt = str(state.get("topic_system_prompt") or "").strip()
    personalization = _personalization_hint(state)
    if topic_prompt:
        return (
            f"{topic_prompt}\n\n"
            "--- TraceCAG Turn Guidance ---\n"
            f"The learner's current CEFR level is: {level}\n"
            f"Difficulty setting for this turn: {difficulty}\n"
            f"{personalization}"
        )

    return (
        "You are Lexi 🦜, a cheerful, witty parrot who is an expert English tutor.\n"
        "You speak in a warm, encouraging tone — like a fun game character guiding an adventure.\n"
        "Keep responses concise (2-4 sentences). Use the knowledge context provided.\n"
        "Gently correct mistakes with encouraging context.\n"
        f"The learner's current CEFR level is: {level}\n"
        f"Difficulty setting for this turn: {difficulty}\n"
        f"{personalization}"
        f"{_RICH_FORMATTING_HINT}"
    )


_RICH_FORMATTING_HINT = (
    "\nWhen it genuinely helps — comparing two grammar forms/tenses/words, or "
    "summarizing multiple facts — use a markdown table (`| Col | Col |`) instead of "
    "prose. Skip the table for short answers where it wouldn't add clarity.\n"
    "For numeric data (scores, progress, counts), you may add ONE fenced "
    '```chart block right after your sentence, containing only compact JSON: '
    '{"type":"bar|line|pie","title":"...","labels":["A","B"],'
    '"series":[{"name":"...","values":[1,2]}]}. Omit it unless there\'s real '
    "data to plot — never invent numbers.\n"
)


def _compute_difficulty_ramp(session_turn: int, overall_score: float) -> str:
    """
    PCC difficulty signal based on session progress + learner performance.

    Returns: 'gentle' | 'standard' | 'challenging'
      - gentle:     first 3 turns or score < 0.50
      - standard:   turns 3-8 or score 0.50-0.70
      - challenging: turns 8+ with score >= 0.70
    """
    if session_turn < 3 or overall_score < 0.50:
        return "gentle"
    if session_turn < 8 or overall_score < 0.70:
        return "standard"
    return "challenging"


def build_generation_prompt(
    state: Dict[str, Any],
) -> tuple[str, List[Dict[str, Any]]]:
    """Extract (system_prompt, messages) from raw pipeline state.

    Used by the streaming endpoint so it can call the LLM with streaming
    enabled after the rest of the pipeline (KG, diagnosis, retrieval) has
    prepared the context.
    """
    errors = state.get("diagnosis_errors", [])
    intent = state.get("diagnosis_intent", "correct")
    level = (state.get("learner_profile") or {}).get("level", "B1")
    user_input = str(state.get("user_input") or "")
    context = str(state.get("retrieved_context") or "")
    native_hint = state.get("native_hint")
    session_turn = len(state.get("conversation_history") or [])
    prev_overall = state.get("overall_score", 0.5)
    fluency_score = state.get("fluency_score", 0.8)
    error_count = len(errors)

    difficulty = _compute_difficulty_ramp(session_turn, prev_overall)

    if intent == "explain" and fluency_score > 0.7:
        strategy = "socratic"
    elif error_count == 0:
        strategy = "praise"
    elif error_count <= 2:
        strategy = "feedback"
    else:
        strategy = "scaffold"

    system_prompt = _build_base_system_prompt(state, level, difficulty)
    if context:
        system_prompt += f"\n--- Knowledge Graph Context ---\n{context}\n"

    if strategy == "socratic":
        system_prompt += (
            "\nStrategy: SOCRATIC. Guide through short questions, don't reveal answer.\n"
        )
        if errors:
            hints = "\n".join(
                f"- '{e.get('span','')}' → '{e.get('correction','')}'"
                for e in errors[:3]
            )
            system_prompt += f"\n--- Errors (hints only) ---\n{hints}\n"
    elif errors:
        errs_text = "\n".join(
            f"- '{e.get('span','')}' → '{e.get('correction','')}' ({e.get('explanation','')})"
            for e in errors[:3]
        )
        system_prompt += f"\n--- Errors Found ---\n{errs_text}\n"
        system_prompt += f"Strategy: {strategy}. Weave corrections naturally.\n"
    else:
        system_prompt += "\nNo errors found — praise the learner's effort!\n"

    if native_hint:
        system_prompt += f"\n--- Native-Language Hint ---\n{native_hint}\n"

    messages: List[Dict[str, Any]] = [{"role": "system", "content": system_prompt}]
    for msg in (state.get("conversation_history") or [])[-12:]:
        role = msg.get("role")
        content = msg.get("content", "")
        if role and content:
            messages.append({"role": role, "content": content})
        elif msg.get("user"):
            messages.append({"role": "user", "content": msg["user"]})
            if msg.get("ai"):
                messages.append({"role": "assistant", "content": msg["ai"]})
    messages.append({"role": "user", "content": user_input})

    return system_prompt, messages


async def stream_llm_tokens(
    *,
    system_prompt: str,
    messages: List[Dict[str, Any]],
    user_input: str,
    max_tokens: int = 512,
    allow_gemini_fallback: bool = True,
    provider_info: Dict[str, str] | None = None,
) -> "AsyncGenerator[str, None]":
    """Stream tokens from Groq (preferred) then Gemini as fallback.

    Yields raw text deltas as they arrive from the provider.
    Falls back silently to Gemini if Groq is unavailable or rate-limited.

    If `provider_info` is passed, it is filled in-place with the provider
    that actually served the tokens (`{"provider": "groq"|"gemini", "model": ...}`)
    once the generator is exhausted — callers that need to know which
    provider served the request (e.g. for telemetry/caching) should not
    guess from env vars, since Groq can fail mid-stream and fall back.
    """

    groq_admitted = False
    groq_model_used = os.getenv("GROQ_MODEL", "qwen/qwen3.6-27b")

    async def _try_groq() -> "AsyncGenerator[str, None]":
        nonlocal groq_admitted
        from api.core.groq_key_pool import record_groq_key_usage, release_groq_key, try_acquire_groq_key

        if _provider_is_disabled("groq"):
            return
        groq_key = await try_acquire_groq_key(estimated_tokens=max_tokens)
        groq_model = groq_model_used
        if not groq_key:
            return
        groq_admitted = True

        # Disable Qwen3 thinking mode to prevent thinking tokens consuming max_tokens budget.
        groq_messages = _qwen_no_think_messages(groq_model, messages)

        client = _get_httpx_client("groq")
        tokens_yielded = 0
        try:
            async with asyncio.timeout(30.0), client.stream(
                "POST",
                "https://api.groq.com/openai/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {groq_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": groq_model,
                    "messages": groq_messages,
                    "max_tokens": max_tokens,
                    "temperature": 0.7,
                    "stream": True,
                    **_qwen_reasoning_overrides(groq_model),
                },
                timeout=25.0,
            ) as resp:
                if resp.status_code != 200:
                    logger.warning("[stream_llm_tokens] Groq status %d", resp.status_code)
                    return
                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    data = line[6:]
                    if data.strip() == "[DONE]":
                        break
                    try:
                        obj = json.loads(data)
                        # Groq reports mid-stream failures (e.g. daily token quota)
                        # as an SSE error frame after a 200 header. Without this the
                        # stream just ends token-less and the caller reports a
                        # generic outage with nothing in the logs.
                        if "error" in obj:
                            logger.warning(
                                "[stream_llm_tokens] Groq mid-stream error: %s",
                                str(obj["error"])[:300],
                            )
                            return
                        delta = obj["choices"][0]["delta"].get("content") or ""
                        if delta:
                            tokens_yielded += len(delta.split())
                            yield delta
                    except Exception as _exc:
                        logger.debug("[generate] ignored: %s", _exc)
                        pass
        except Exception as exc:
            logger.warning("[stream_llm_tokens] Groq stream error: %s", exc)
        finally:
            if groq_key:
                try:
                    try:
                        await record_groq_key_usage(groq_key, max(50, tokens_yielded + 50))
                    except Exception as exc:
                        logger.warning("[stream_llm_tokens] Groq usage accounting failed: %s", exc)
                finally:
                    await release_groq_key(groq_key)

    async def _try_gemini() -> "AsyncGenerator[str, None]":
        gemini_key = os.getenv("GEMINI_API_KEY", "")
        if not gemini_key or _provider_is_disabled("gemini"):
            return

        url = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            "gemini-2.0-flash:streamGenerateContent?alt=sse"
        )
        request_body = {
            "contents": [{"role": "user", "parts": [{"text": user_input}]}],
            "systemInstruction": {"parts": [{"text": system_prompt}]},
            "generationConfig": {"maxOutputTokens": max_tokens},
        }
        client = _get_httpx_client("gemini")
        try:
            async with client.stream(
                "POST",
                url,
                headers={"x-goog-api-key": gemini_key},
                json=request_body,
                timeout=25.0,
            ) as resp:
                if resp.status_code != 200:
                    logger.warning("[stream_llm_tokens] Gemini status %d", resp.status_code)
                    return
                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    data = line[6:]
                    try:
                        obj = json.loads(data)
                        text = (
                            obj.get("candidates", [{}])[0]
                            .get("content", {})
                            .get("parts", [{}])[0]
                            .get("text", "")
                        )
                        if text:
                            yield text
                    except Exception as _exc:
                        logger.debug("[generate] ignored: %s", _exc)
                        pass
        except Exception as exc:
            logger.warning("[stream_llm_tokens] Gemini stream error: %s", exc)

    # Try Groq first; if it yields nothing, fall back to Gemini
    got_tokens = False
    groq_stream = _try_groq()
    try:
        async for token in groq_stream:
            got_tokens = True
            yield token
    finally:
        await groq_stream.aclose()

    if got_tokens:
        if provider_info is not None:
            provider_info["provider"] = "groq"
            provider_info["model"] = groq_model_used
        return

    if not allow_gemini_fallback:
        if not groq_admitted:
            raise ProviderBusyError("Groq voice capacity exhausted")
        raise RuntimeError("Groq admitted the turn but returned no token")

    gemini_yielded = False
    async for token in _try_gemini():
        gemini_yielded = True
        yield token
    if gemini_yielded and provider_info is not None:
        provider_info["provider"] = "gemini"
        provider_info["model"] = "gemini-2.0-flash"


async def generate_node(state: TraceCAGState) -> Dict[str, Any]:
    """
    Generate the tutor response using LLM grounded in KG evidence.

    This node calls the LLM fallback chain (Groq → Gemini → Ollama)
    with the Lexi persona, KG context, and diagnosis data injected
    into the system prompt. This is the SINGLE place where LLM
    generation happens — callers should NOT make a separate LLM call.
    """
    # When the streaming endpoint handles generation externally, skip this node.
    if state.get("generation_policy") == "skip":
        return {}

    logger.info("[generate_node] Generating grounded tutor response...")
    start_time = time.time()

    errors = state.get("diagnosis_errors", [])
    intent = state.get("diagnosis_intent", "correct")
    level = state.get("learner_profile", {}).get("level", "B1")
    user_input = state.get("user_input", "")
    context = state.get("retrieved_context", "")
    jit_soft_graph = str(state.get("jit_soft_graph") or "").strip()
    native_hint = state.get("native_hint")
    benchmark_task = state.get("benchmark_task")

    if benchmark_task in {"multihop_qa", "retrieval_qa"}:
        return await _generate_benchmark_qa_response(state, start_time)

    # Determine strategy (paper Eq. strategy)
    error_count = len(errors)
    fluency_score = state.get("fluency_score", 0.8)

    if intent == "explain" and fluency_score > 0.7:
        strategy = "socratic"
    elif error_count == 0:
        strategy = "praise"
    elif error_count <= 2:
        strategy = "feedback"
    else:
        strategy = "scaffold"

    generation_policy = state.get("generation_policy", "auto")
    if generation_policy == "template":
        logger.warning("[generate_node] generation_policy='template' is deprecated; using extractive policy")
        generation_policy = "extractive"

    if generation_policy == "extractive":
        response = _generate_extractive_fallback_response(errors, strategy, user_input, context)
        model_used = "extractive_policy"

        if strategy == "socratic":
            next_action = "ask"
        elif error_count == 0:
            next_action = "continue"
        elif error_count <= 2:
            next_action = "hint"
        else:
            next_action = "correct"

        grammar_score = state.get("grammar_score", 0.8)
        fluency_score = state.get("fluency_score", 0.8)
        vocab_level = state.get("vocabulary_level", "B1")
        overall_score = EvaluationAgent.compute_overall_score(grammar_score, fluency_score, vocab_level)

        _update_ranker_from_generation(
            question=user_input,
            response=response,
            retrieval_trace=list(state.get("retrieval_trace") or []),
        )

        if state.get("cache_policy", "on") == "on":
            try:
                await _write_cache_entry(_state_with_policy_dependency(state), response, strategy, errors, overall_score, context, model_used=model_used)
            except Exception as e:
                logger.debug(f"[generate_node] Cache write failed: {e}")

        latency_ms = int((time.time() - start_time) * 1000)

        return {
            "tutor_response": response,
            "strategy": strategy,
            "next_action": next_action,
            "overall_score": overall_score,
            "ttft_ms": latency_ms,
            "models_used": [model_used],
        }

    # Build system prompt with Lexi persona + grounded context
    session_turn = len(state.get("conversation_history", []))
    prev_overall = state.get("overall_score", 0.5)
    difficulty = _compute_difficulty_ramp(session_turn, prev_overall)

    system_prompt = _build_base_system_prompt(state, level, difficulty)

    if context:
        system_prompt += f"\n--- Knowledge Graph Context ---\n{context}\n"

    if strategy == "socratic":
        system_prompt += (
            "\nStrategy: SOCRATIC. The learner asked for an explanation and is fairly fluent.\n"
            "Guide them through a chain of short questions so they discover the answer themselves.\n"
            "Do NOT give the answer directly — instead ask 1-2 leading questions.\n"
        )
        if errors:
            errors_text = "\n".join([
                f"- '{e.get('span','')}' → '{e.get('correction','')}' ({e.get('explanation','')})"
                for e in errors[:3]
            ])
            system_prompt += f"\n--- Errors Found (use as hints, don't reveal directly) ---\n{errors_text}\n"
    elif errors:
        errors_text = "\n".join([
            f"- '{e.get('span','')}' → '{e.get('correction','')}' ({e.get('explanation','')})"
            for e in errors[:3]
        ])
        system_prompt += f"\n--- Errors Found ---\n{errors_text}\n"
        system_prompt += f"Strategy: {strategy}. Weave corrections naturally into your response.\n"
    else:
        system_prompt += "\nNo errors found — praise the learner's effort!\n"

    if native_hint:
        system_prompt += f"\n--- Native-Language Hint (for reference) ---\n{native_hint}\n"

    response = ""
    model_used = "llm_unavailable"

    local_llama_enabled = _env_flag("TRACECAG_ENABLE_LOCAL_LLAMA_KV", False)
    if local_llama_enabled and not response:
        try:
            local_llama = get_local_llama_kv_service()
            local_result = await local_llama.generate(
                session_id=str(state.get("session_id") or "default"),
                core_system_prompt=_LOCAL_LLAMA_CORE_SYSTEM_PROMPT,
                dynamic_system_prompt=system_prompt,
                user_query=user_input,
                soft_graph="" if "[JIT_SOFT_GRAPH]" in context else jit_soft_graph,
            )
            if local_result and str(local_result.get("text") or "").strip():
                response = str(local_result.get("text") or "").strip()
                model_used = str(local_result.get("model") or "llama_cpp_kv")
        except Exception as e:
            logger.warning(f"[generate_node] Local llama KV path failed, fallback to provider chain: {e}")

    # Call LLM via fallback chain (Groq → Gemini → Ollama)
    if not response:
        response = ""
        model_used = "llm_unavailable"

    try:
        messages = [{"role": "system", "content": system_prompt}]

        # Inject conversation history (last 6 turns = up to 12 messages)
        history = state.get("conversation_history", [])
        for msg in history[-12:]:
            role = msg.get("role")
            content = msg.get("content", "")
            if role and content:
                # Standard {"role": "user"/"assistant", "content": "..."} format
                messages.append({"role": role, "content": content})
            elif msg.get("user"):
                # ConversationCache {"user": "...", "ai": "..."} format
                messages.append({"role": "user", "content": msg["user"]})
                if msg.get("ai"):
                    messages.append({"role": "assistant", "content": msg["ai"]})

        messages.append({"role": "user", "content": user_input})

        if not response:
            # Race Groq and Gemini concurrently; first successful response wins.
            # Ollama is kept as last-resort with a tighter 15s timeout.
            import asyncio as _asyncio
            from api.core.groq_key_pool import get_available_groq_key, record_groq_key_usage

            # The pool debits this against each key's per-minute budget, so it
            # has to cover the whole request, not just the reply. `messages`
            # already holds the system prompt, the KG context inside it and up
            # to 12 history turns; a grounded first turn alone measures ~850
            # tokens, so the flat 512 under-counted it by at least 1.7x and the
            # pool handed out keys it had already spent, which Groq answered
            # with 429 and a several-minute Retry-After.
            _prompt_chars = sum(len(str(m.get("content") or "")) for m in messages)
            groq_key = await get_available_groq_key(
                estimated_tokens=512 + _prompt_chars // 4
            )
            groq_model = os.getenv("GROQ_MODEL", "qwen/qwen3.6-27b")
            gemini_key = os.getenv("GEMINI_API_KEY", "")

            # Disable Qwen3 thinking to keep token budget for actual response.
            _groq_messages = _qwen_no_think_messages(groq_model, messages)

            async def _try_groq():
                if not groq_key:
                    return None, None
                try:
                    resp = await _throttled_post_json(
                        provider="groq",
                        url="https://api.groq.com/openai/v1/chat/completions",
                        headers={"Authorization": f"Bearer {groq_key}", "Content-Type": "application/json"},
                        payload={
                            "model": groq_model,
                            "messages": _groq_messages,
                            "max_tokens": 512,
                            "temperature": 0.7,
                            **_qwen_reasoning_overrides(groq_model),
                        },
                        timeout=20.0,
                    )
                    if resp is not None and resp.status_code == 200:
                        data = resp.json()
                        tokens = data.get("usage", {}).get("total_tokens", 500)
                        await record_groq_key_usage(groq_key, tokens)
                        return data["choices"][0]["message"]["content"], f"groq/{groq_model}"
                except Exception as e:
                    logger.warning(f"[generate_node] Groq failed: {e}")
                return None, None

            async def _try_gemini():
                if not gemini_key:
                    return None, None
                try:
                    gemini_contents = [{"role": "user", "parts": [{"text": user_input}]}]
                    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
                    request_body = {
                        "contents": gemini_contents,
                        "systemInstruction": {"parts": [{"text": system_prompt}]},
                    }
                    resp = await _throttled_post_json(
                        provider="gemini",
                        url=url,
                        payload=request_body,
                        headers={"x-goog-api-key": gemini_key},
                        timeout=20.0,
                    )
                    if resp is not None and resp.status_code == 200:
                        candidates = resp.json().get("candidates", [])
                        if candidates:
                            return candidates[0]["content"]["parts"][0]["text"], "gemini-2.0-flash"
                except Exception as e:
                    logger.warning(f"[generate_node] Gemini failed: {e}")
                return None, None

            # Launch both concurrently; pick first non-None result.
            tasks = [_asyncio.ensure_future(_try_groq()), _asyncio.ensure_future(_try_gemini())]
            done, pending = await _asyncio.wait(tasks, return_when=_asyncio.FIRST_COMPLETED)
            for task in done:
                try:
                    _text, _model = task.result()
                    if _text:
                        response = _text
                        model_used = _model
                        break
                except Exception as _exc:
                    logger.debug("[generate] ignored: %s", _exc)
                    pass
            # If winner found, cancel the loser immediately.
            if response:
                for p in pending:
                    p.cancel()
            else:
                # Wait for the second one too before falling back to Ollama.
                if pending:
                    done2, _ = await _asyncio.wait(pending, timeout=15.0)
                    for task in done2:
                        try:
                            _text, _model = task.result()
                            if _text:
                                response = _text
                                model_used = _model
                                break
                        except Exception as _exc:
                            logger.debug("[generate] ignored: %s", _exc)
                            pass

            # Ollama — last resort, tight 15s timeout.
            if not response:
                from api.core.config import settings
                ollama_url = settings.OLLAMA_BASE_URL
                ollama_model = os.getenv("OLLAMA_MODEL", "lexilingo-qwen3-1.7b")
                try:
                    resp = await _throttled_post_json(
                        provider="ollama",
                        url=f"{ollama_url}/api/chat",
                        payload={
                            "model": ollama_model,
                            "messages": messages,
                            "stream": False,
                            "options": {"num_predict": 256, "temperature": 0.7},
                        },
                        timeout=15.0,
                        max_retries=1,
                    )
                    if resp is not None and resp.status_code == 200:
                        response = resp.json().get("message", {}).get("content", "")
                        model_used = f"ollama/{ollama_model}"
                except Exception as e:
                    logger.warning(f"[generate_node] Ollama failed: {e}")

    except Exception as e:
        logger.error(f"[generate_node] LLM chain error: {e}")

    # 4. Safe conversational fallback. Extractive output is reserved for the
    # explicit benchmark/extractive branches above and must not leak raw KG context.
    if not response:
        response = SAFE_TUTOR_FALLBACK
        model_used = "safe_tutor_fallback"

    # Determine next action
    if strategy == "socratic":
        next_action = "ask"
    elif error_count == 0:
        next_action = "continue"
    elif error_count <= 2:
        next_action = "hint"
    else:
        next_action = "correct"

    # Calculate overall score
    grammar_score = state.get("grammar_score", 0.8)
    fluency_score = state.get("fluency_score", 0.8)
    vocab_level = state.get("vocabulary_level", "B1")
    overall_score = EvaluationAgent.compute_overall_score(grammar_score, fluency_score, vocab_level)

    _update_ranker_from_generation(
        question=user_input,
        response=response,
        retrieval_trace=list(state.get("retrieval_trace") or []),
    )

    # Generate personalized practice exercises via ContentAutoGenerator (cag_service)
    action_plan = []
    if errors or intent == "practice":
        try:
            from api.services.cag_service import ContentAutoGenerator
            cag_gen = ContentAutoGenerator()
            err_types = [err.get("type", "grammar") for err in errors if isinstance(err, dict)]
            if not err_types:
                err_types = ["grammar"]

            first_err_type = err_types[0] if errors else "vocabulary"
            if "vocab" in first_err_type.lower() or intent == "practice":
                vocab_ex = cag_gen.generate_vocabulary_exercise(
                    level=level,
                    error_patterns=err_types if errors else None,
                    count=3
                )
                action_plan.append({
                    "action": "practice",
                    "type": "vocabulary",
                    "concept": vocab_ex.get("topic", ""),
                    "count": len(vocab_ex.get("words", [])),
                    "exercise": vocab_ex
                })
            else:
                grammar_drill = cag_gen.generate_grammar_drill(
                    level=level,
                    error_patterns=err_types,
                    count=3
                )
                action_plan.append({
                    "action": "practice",
                    "type": "grammar",
                    "concept": grammar_drill.get("grammar_point", ""),
                    "count": len(grammar_drill.get("exercises", [])),
                    "exercise": grammar_drill
                })
        except Exception as cag_err:
            logger.warning(f"[generate_node] Failed to generate CAG practice: {cag_err}")

    state["action_plan"] = action_plan

    # Store response in Redis cache for future hits
    if state.get("cache_policy", "on") == "on" and model_used != "safe_tutor_fallback":
        try:
            # ── Tiered Cache Management (L0/L1 Promotion) ─────────────
            # Nếu thông tin từ L2 được sử dụng, kiểm tra thăng hạng
            doc_service = get_doc_intel_service()
            trace = state.get("retrieval_trace", [])
            is_l2_used = any(t.get("item_id", "").startswith("ext_") for t in trace[:3])

            if is_l2_used:
                for t in trace[:3]:
                    if t.get("item_id", "").startswith("ext_"):
                        chunk_id = str(t.get("item_id") or "").replace("ext_", "")
                        if doc_service.should_promote_to_cache(chunk_id):
                            logger.info(f"[cache_promotion] Chunk {chunk_id[:8]} promoted to L1 cache")
                            await _write_cache_entry(_state_with_policy_dependency(state), response, strategy, errors, overall_score, context)
                            break
            else:
                # Mặc định cache cho các luồng KG/Rules để tối ưu tốc độ
                await _write_cache_entry(_state_with_policy_dependency(state), response, strategy, errors, overall_score, context)
        except Exception as e:
            logger.debug(f"[generate_node] Cache write failed: {e}")

    latency_ms = int((time.time() - start_time) * 1000)
    logger.info(f"[generate_node] Generated response via {model_used} in {latency_ms}ms")

    return {
        "tutor_response": response,
        "strategy": strategy,
        "next_action": next_action,
        "overall_score": overall_score,
        "action_plan": action_plan,
        "ttft_ms": latency_ms,
        "models_used": [model_used],
    }
