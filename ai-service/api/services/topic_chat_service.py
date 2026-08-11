"""Topic Chat Service — extracted business logic from send_topic_message route."""

import asyncio
import json
import logging
import re
import time
import uuid
from contextlib import suppress
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, AsyncGenerator, Callable, Coroutine

from api.repositories.topic_chat_repository import TopicChatRepository
from api.services.lexi_chat_service import HEARTBEAT_INTERVAL_S
from api.services.subgraph_hot_cache import get_subgraph
import os


def _env_float(name: str, default: float, minimum: float = 0.0) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return max(minimum, float(raw))
    except ValueError:
        return default

logger = logging.getLogger(__name__)

SAFE_FIXED_RESPONSE = (
    "I'm sorry, I can't respond right now. "
    "Please try again shortly."
)

_PRIMARY_TIMEOUT = _env_float("TOPIC_TRACECAG_TIMEOUT_SEC", 12.0)
_RETRY_TIMEOUT = _env_float("TOPIC_TRACECAG_RETRY_TIMEOUT_SEC", 6.0)


def sanitize_topic_response(text: str) -> str:
    """Best-effort cleanup for malformed JSON tails leaked by model outputs.

    Shared by the JSON route and the SSE stream generator below — moved here
    (was route-local `_sanitize_topic_response`) so both call sites use the
    exact same cleanup instead of drifting apart.
    """
    candidate = (text or "").strip()
    if not candidate:
        return candidate

    # Common case: normal sentence followed by broken JSON tail like `],"e":[]}`.
    last_sentence_end = max(candidate.rfind("."), candidate.rfind("!"), candidate.rfind("?"))
    if 0 <= last_sentence_end < len(candidate) - 1:
        tail = candidate[last_sentence_end + 1 :].strip()
        has_json_punct = any(ch in tail for ch in "{}[]") and ":" in tail
        long_alpha_tokens = re.findall(r"[A-Za-z]{2,}", tail)
        if tail and has_json_punct and not long_alpha_tokens:
            candidate = candidate[: last_sentence_end + 1].strip()

    return candidate


async def _run_with_heartbeats(
    make_coro: Callable[[], Coroutine[Any, Any, Any]],
    timeout_s: float,
) -> AsyncGenerator[Any, None]:
    """Run `make_coro()` to completion, yielding SSE heartbeat strings while
    it's in flight so the caller can forward them to the client and keep
    proxies from treating the connection as idle. The final yielded item is
    the coroutine's actual result (never a str, since heartbeats are).

    Raises asyncio.TimeoutError if `timeout_s` elapses before completion.
    """
    task = asyncio.ensure_future(make_coro())
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout_s
    while not task.done():
        if loop.time() >= deadline:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task
            raise asyncio.TimeoutError(f"deadline of {timeout_s}s exceeded")
        remaining = max(0.05, min(HEARTBEAT_INTERVAL_S, deadline - loop.time()))
        try:
            await asyncio.wait_for(asyncio.shield(task), timeout=remaining)
        except asyncio.TimeoutError:
            yield "event: heartbeat\ndata: {}\n\n"
    yield await task


async def resolve_kg_seeds(
    session: dict[str, Any],
    redis_client: Any,
) -> list[str]:
    """Load KG seed concepts from session doc, fallback to subgraph cache."""
    kg_seeds: list[str] = list(session.get("kg_seed_concepts") or [])
    if not kg_seeds:
        try:
            subgraph = await get_subgraph(session.get("story_id", ""), redis_client)
            if subgraph:
                kg_seeds = subgraph.get("seed_concepts", [])
        except Exception as exc:
            logger.debug("[topic_chat_service] ignored subgraph fallback error: %s", exc)
    return kg_seeds


@dataclass
class TracecagResult:
    ai_response: str
    llm_metadata: dict[str, Any]


async def call_tracecag_with_retry(
    message: str,
    session_id: str,
    user_id: str,
    difficulty_level: str,
    conversation_history: list[dict[str, Any]],
    kg_seeds: list[str],
    preferred_llm: str,
    topic_system_prompt: str | None = None,
    primary_timeout: float = _PRIMARY_TIMEOUT,
    retry_timeout: float = _RETRY_TIMEOUT,
) -> TracecagResult:
    """Primary TraceCAG call -> degraded retry -> SAFE_FIXED_RESPONSE fallback."""
    from api.services.orchestrator import get_orchestrator

    try:
        graph_start = time.time()
        orchestrator = await get_orchestrator()
        graph_result = await asyncio.wait_for(
            orchestrator.process(
                user_input=message,
                session_id=session_id,
                user_id=user_id,
                learner_profile={"level": difficulty_level},
                conversation_history=conversation_history[-6:],
                retrieval_policy="rapid",
                diagnosis_policy="rules",
                generation_policy="auto",
                topic_system_prompt=topic_system_prompt,
                kg_seed_concepts=kg_seeds or None,
                # ponytail: topic persona changes output; include prompt in cache key before enabling.
                cache_policy="off",
            ),
            timeout=primary_timeout,
        )
        ai_response = str(graph_result.get("tutor_response") or "").strip()
        if not ai_response:
            raise RuntimeError("TraceCAG returned empty tutor_response")
        graph_metadata = graph_result.get("metadata", {}) or {}
        llm_metadata = {
            "provider": "trace-cag",
            "model": ", ".join(graph_metadata.get("models_used") or ["trace-cag_pipeline"]),
            "latency_ms": int((time.time() - graph_start) * 1000),
            "fallback_used": preferred_llm != "trace-cag",
        }
        logger.info("Topic chat response via TraceCAG")
        return TracecagResult(ai_response=ai_response, llm_metadata=llm_metadata)

    except Exception as graph_err:
        logger.error("TraceCAG failed for topic chat (primary): %s", graph_err)

    try:
        retry_start = time.time()
        orchestrator = await get_orchestrator()
        retry_result = await asyncio.wait_for(
            orchestrator.process(
                user_input=message,
                session_id=session_id,
                user_id=user_id,
                learner_profile={"level": difficulty_level},
                conversation_history=[],
                cache_policy="off",
                retrieval_policy="rapid",
                diagnosis_policy="rules",
                generation_policy="auto",
                topic_system_prompt=topic_system_prompt,
            ),
            timeout=retry_timeout,
        )
        ai_response = str(retry_result.get("tutor_response") or "").strip()
        if not ai_response:
            raise RuntimeError("TraceCAG degraded retry returned empty tutor_response")
        retry_meta = retry_result.get("metadata", {}) or {}
        llm_metadata = {
            "provider": "trace-cag",
            "model": ", ".join(retry_meta.get("models_used") or ["trace-cag_retry"]),
            "latency_ms": int((time.time() - retry_start) * 1000),
            "fallback_used": True,
            "retry_mode": "trace-cag_degraded",
        }
        return TracecagResult(ai_response=ai_response, llm_metadata=llm_metadata)

    except Exception as retry_err:
        logger.error("TraceCAG failed for topic chat (degraded retry): %s", retry_err)
        return TracecagResult(
            ai_response=SAFE_FIXED_RESPONSE,
            llm_metadata={
                "provider": "trace-cag_safe_response",
                "model": "safe_fixed_response",
                "latency_ms": 0,
                "fallback_used": True,
            },
        )


async def persist_topic_turn(
    session_id: str,
    user_id: str,
    message: str,
    ai_response: str,
    repo: TopicChatRepository,
) -> str:
    """Insert user + AI messages, update session activity. Returns ai_message_id."""
    now = datetime.now(timezone.utc)

    ai_message_id = str(uuid.uuid4())
    await repo.insert_messages_bulk([
        {
            "message_id": str(uuid.uuid4()),
            "session_id": session_id,
            "user_id": user_id,
            "content": message,
            "role": "user",
            "timestamp": now,
        },
        {
            "message_id": ai_message_id,
            "session_id": session_id,
            "content": ai_response,
            "role": "assistant",
            "timestamp": now,
        },
    ])
    await repo.update_session_activity(session_id, now, message_count_increment=2)
    return ai_message_id


async def stream_tracecag_topic_message(
    *,
    message: str,
    session_id: str,
    user_id: str,
    difficulty_level: str,
    conversation_history: list[dict[str, Any]],
    kg_seeds: list[str],
    topic_system_prompt: str | None,
    repo: TopicChatRepository,
    quota: Any,
    start_time: float,
    request_id: str,
    primary_timeout: float = _PRIMARY_TIMEOUT,
    retry_timeout: float = _RETRY_TIMEOUT,
) -> AsyncGenerator[str, None]:
    """SSE generator for streaming topic chat.

    Events: thinking / heartbeat / chunk / done / error.

    Mirrors call_tracecag_with_retry's 2-tier fallback (primary -> degraded
    retry -> SAFE_FIXED_RESPONSE) so the streaming endpoint is no less
    resilient than the JSON one, but calls analyze_for_streaming
    (generation_policy="skip") instead of orchestrator.process() so the full
    KG/diagnosis/retrieval context is still built, and streams the LLM call
    here instead of inside the graph. Provider tokens are buffered and
    sanitized (EducationalHintsParser + sanitize_topic_response) BEFORE any
    text reaches the client — chunks are words of the already-clean
    response, never raw provider deltas, so internal markers can't leak.
    """
    from api.core.audit_emitter import emit_ai_audit_event
    from api.services.educational_hints_parser import EducationalHintsParser
    from api.services.orchestrator import get_orchestrator
    from api.services.trace_cag.nodes_v2 import build_generation_prompt, stream_llm_tokens

    yield "event: thinking\ndata: {}\n\n"

    orchestrator = None
    try:
        async for item in _run_with_heartbeats(get_orchestrator, primary_timeout):
            if isinstance(item, str):
                yield item
            else:
                orchestrator = item
    except Exception as exc:
        logger.error("Topic /stream orchestrator warm failed: %s", exc)
        yield (
            f"event: error\ndata: "
            f"{json.dumps({'error': 'Service is starting up. Please try again.'})}\n\n"
        )
        return

    def _prep_kwargs(hist: list[dict[str, Any]]) -> dict[str, Any]:
        return dict(
            user_input=message,
            session_id=session_id,
            user_id=user_id,
            learner_profile={"level": difficulty_level},
            conversation_history=hist,
            retrieval_policy="rapid",
            diagnosis_policy="rules",
            topic_system_prompt=topic_system_prompt,
            cache_policy="off",
        )

    raw_state: dict[str, Any] | None = None
    context_meta: dict[str, Any] = {}

    try:
        prep_start = time.time()
        async for item in _run_with_heartbeats(
            lambda: orchestrator.pipeline.analyze_for_streaming(
                **_prep_kwargs(conversation_history[-6:]),
                kg_seed_concepts=kg_seeds or None,
            ),
            primary_timeout,
        ):
            if isinstance(item, str):
                yield item
            else:
                raw_state = item
        context_meta = {
            "fallback_used": False,
            "context_latency_ms": int((time.time() - prep_start) * 1000),
        }
    except Exception as primary_err:
        logger.error("Topic /stream context prep failed (primary): %s", primary_err)
        raw_state = None

    if raw_state is None:
        try:
            retry_start = time.time()
            async for item in _run_with_heartbeats(
                lambda: orchestrator.pipeline.analyze_for_streaming(
                    **_prep_kwargs([]),
                ),
                retry_timeout,
            ):
                if isinstance(item, str):
                    yield item
                else:
                    raw_state = item
            context_meta = {
                "fallback_used": True,
                "retry_mode": "trace-cag_degraded",
                "context_latency_ms": int((time.time() - retry_start) * 1000),
            }
        except Exception as retry_err:
            logger.error("Topic /stream context prep failed (degraded retry): %s", retry_err)
            raw_state = None

    provider_info: dict[str, str] = {}
    ai_response = ""
    if raw_state is not None:
        try:
            system_prompt, llm_messages = build_generation_prompt(raw_state)
            tokens: list[str] = []
            async for token in stream_llm_tokens(
                system_prompt=system_prompt,
                messages=llm_messages,
                user_input=message,
                provider_info=provider_info,
            ):
                tokens.append(token)
            ai_response = "".join(tokens).strip()
        except Exception as gen_err:
            logger.error("Topic /stream LLM generation error: %s", gen_err)
            ai_response = ""

    if ai_response:
        llm_metadata = {
            "provider": "trace-cag",
            "model": f"{provider_info.get('provider', 'unknown')}/{provider_info.get('model', 'unknown')}",
            "latency_ms": context_meta.get("context_latency_ms", 0),
            "fallback_used": context_meta.get("fallback_used", False),
        }
        if "retry_mode" in context_meta:
            llm_metadata["retry_mode"] = context_meta["retry_mode"]
    else:
        ai_response = SAFE_FIXED_RESPONSE
        llm_metadata = {
            "provider": "trace-cag_safe_response",
            "model": "safe_fixed_response",
            "latency_ms": 0,
            "fallback_used": True,
        }

    clean_response, parsed_hints = EducationalHintsParser.parse(ai_response)
    display_response = sanitize_topic_response(clean_response or ai_response)

    educational_hints_dict = None
    if parsed_hints and parsed_hints.has_hints():
        educational_hints_dict = parsed_hints.to_dict()

    for word in (display_response.split(" ") if display_response else []):
        yield f"event: chunk\ndata: {json.dumps({'text': word + ' '})}\n\n"

    ai_message_id = await persist_topic_turn(
        session_id=session_id,
        user_id=user_id,
        message=message,
        ai_response=display_response,
        repo=repo,
    )

    processing_time = int((time.time() - start_time) * 1000)

    done_payload = json.dumps({
        "message_id": ai_message_id,
        "session_id": session_id,
        "ai_response": display_response,
        "clean_response": display_response,
        "educational_hints": educational_hints_dict,
        "processing_time_ms": processing_time,
        "llm_metadata": llm_metadata,
    })
    yield f"event: done\ndata: {done_payload}\n\n"

    logger.info(
        "Topic /stream complete — %dms, model: %s",
        processing_time, llm_metadata.get("model"),
    )
    await emit_ai_audit_event({
        "request_id": request_id,
        "user_id": user_id,
        "endpoint": "topic.send_message.stream",
        "status": "success",
        "session_id": session_id,
        "latency_ms": processing_time,
        "quota": {
            "rpm_used": quota.rpm_used,
            "rpm_limit": quota.rpm_limit,
            "rpd_used": quota.rpd_used,
            "rpd_limit": quota.rpd_limit,
            "tpm_used": quota.tpm_used,
            "tpm_limit": quota.tpm_limit,
            "tpd_used": quota.tpd_used,
            "tpd_limit": quota.tpd_limit,
        },
    })
