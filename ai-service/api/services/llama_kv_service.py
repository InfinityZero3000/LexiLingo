"""Local llama-cpp generation service with KV-cache optimization.

This service is optional and designed for CPU-only local deployments.
It keeps a pinned core prompt in KV cache and evicts transient turn tokens
after each generation to control memory growth.

If llama-cpp is unavailable or misconfigured, callers should fallback to
existing remote/provider generation paths.
"""

from __future__ import annotations

import asyncio
import logging
import os
import re
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class LocalLlamaConfig:
    enabled: bool
    model_path: str
    n_ctx: int
    n_batch: int
    n_threads: int
    n_threads_batch: int
    max_tokens: int
    temperature: float
    top_p: float
    repeat_penalty: float
    keep_session_ms: int


class LocalLlamaKVService:
    """Singleton local llama-cpp service with KV-turn eviction."""

    def __init__(self) -> None:
        self._llm = None
        self._llama_cpp_lib = None
        self._load_lock = asyncio.Lock()
        self._gen_lock = asyncio.Lock()
        self._active_session_id: Optional[str] = None
        self._pinned_token_count: int = 0
        self._core_prompt_cache: str = ""

    async def generate(
        self,
        *,
        session_id: str,
        core_system_prompt: str,
        dynamic_system_prompt: str,
        user_query: str,
        soft_graph: str = "",
    ) -> Optional[Dict[str, Any]]:
        cfg = self._load_config()
        if not cfg.enabled:
            return None

        llm = await self._ensure_model(cfg)
        if llm is None:
            return None

        sid = session_id or "default"

        async with self._gen_lock:
            if self._active_session_id != sid or self._core_prompt_cache != core_system_prompt:
                self._reset_and_pin_core(core_system_prompt)
                self._active_session_id = sid
                self._core_prompt_cache = core_system_prompt

            turn_prompt = self._build_turn_prompt(
                dynamic_system_prompt=dynamic_system_prompt,
                user_query=user_query,
                soft_graph=soft_graph,
            )
            turn_tokens = llm.tokenize(turn_prompt.encode("utf-8"), add_bos=False)
            self._ensure_context_room(cfg, len(turn_tokens))

            turn_start = self._n_tokens()
            out_text = self._generate_text(
                prompt_tokens=turn_tokens,
                max_tokens=cfg.max_tokens,
                temperature=cfg.temperature,
                top_p=cfg.top_p,
                repeat_penalty=cfg.repeat_penalty,
            )
            turn_end = self._n_tokens()
            self._evict_turn_segment(turn_start, turn_end)

            return {
                "text": out_text,
                "model": "llama_cpp_kv",
                "meta": {
                    "session_id": sid,
                    "turn_start": turn_start,
                    "turn_end": turn_end,
                    "n_ctx": cfg.n_ctx,
                },
            }

    async def _ensure_model(self, cfg: LocalLlamaConfig):
        if self._llm is not None:
            return self._llm

        async with self._load_lock:
            if self._llm is not None:
                return self._llm

            if not cfg.model_path or not os.path.exists(cfg.model_path):
                logger.warning("[LocalLlamaKVService] Model path missing or not found: %s", cfg.model_path)
                return None

            try:
                from llama_cpp import Llama
                from llama_cpp import llama_cpp as llama_cpp_lib
            except Exception as exc:
                logger.warning("[LocalLlamaKVService] llama-cpp-python unavailable: %s", exc)
                return None

            try:
                self._llm = await asyncio.to_thread(
                    Llama,
                    model_path=cfg.model_path,
                    n_ctx=cfg.n_ctx,
                    n_batch=cfg.n_batch,
                    n_threads=cfg.n_threads,
                    n_threads_batch=cfg.n_threads_batch,
                    n_gpu_layers=0,
                    f16_kv=True,
                    use_mmap=True,
                    use_mlock=False,
                    verbose=False,
                )
                self._llama_cpp_lib = llama_cpp_lib
                logger.info("[LocalLlamaKVService] Loaded local llama model: %s", cfg.model_path)
                return self._llm
            except Exception as exc:
                logger.warning("[LocalLlamaKVService] Failed to initialize local llama model: %s", exc)
                self._llm = None
                return None

    def _reset_and_pin_core(self, core_system_prompt: str) -> None:
        if self._llm is None:
            return

        self._llm.reset()
        core_prompt = (
            "<|system|>\n"
            f"{core_system_prompt.strip()}\n"
            "<|assistant|>\n"
        )
        core_tokens = self._llm.tokenize(core_prompt.encode("utf-8"), add_bos=True)
        self._llm.eval(core_tokens)
        self._pinned_token_count = self._n_tokens()

    def _build_turn_prompt(self, *, dynamic_system_prompt: str, user_query: str, soft_graph: str) -> str:
        if soft_graph:
            graph_block = f"SOFT_GRAPH_JIT(JSON):\n{soft_graph}\n"
        else:
            graph_block = ""
        return (
            "<|user|>\n"
            f"{dynamic_system_prompt.strip()}\n\n"
            f"{graph_block}"
            f"RAW_QUERY:\n{user_query}\n"
            "Return a grounded, concise answer.\n"
            "<|assistant|>\n"
        )

    def _ensure_context_room(self, cfg: LocalLlamaConfig, incoming_tokens: int) -> None:
        projected = self._n_tokens() + incoming_tokens + cfg.max_tokens
        if projected >= cfg.n_ctx:
            # Reset to pinned prompt when nearing context limit.
            self._set_n_tokens(self._pinned_token_count)

    def _generate_text(
        self,
        *,
        prompt_tokens,
        max_tokens: int,
        temperature: float,
        top_p: float,
        repeat_penalty: float,
    ) -> str:
        if self._llm is None:
            return ""

        chunks = []
        generated = 0
        generator = self._llm.generate(
            prompt_tokens,
            temp=temperature,
            top_p=top_p,
            repeat_penalty=repeat_penalty,
            reset=False,
        )
        for token in generator:
            generated += 1
            piece = self._llm.detokenize([token]).decode("utf-8", errors="ignore")
            chunks.append(piece)
            if generated >= max_tokens:
                break
            if self._contains_stop("".join(chunks)):
                break

        text = "".join(chunks)
        return self._trim_stop(text).strip()

    def _evict_turn_segment(self, start_pos: int, end_pos: int) -> None:
        if self._llm is None or end_pos <= start_pos:
            return

        removed = self._kv_cache_seq_rm(start_pos, end_pos)
        if removed:
            self._set_n_tokens(self._pinned_token_count)
        else:
            # Conservative fallback if low-level API not exposed in this build.
            self._llm.reset()
            self._set_n_tokens(0)
            self._active_session_id = None
            self._core_prompt_cache = ""

    def _kv_cache_seq_rm(self, p0: int, p1: int) -> bool:
        if self._llm is None:
            return False

        try:
            if hasattr(self._llm, "kv_cache_seq_rm"):
                self._llm.kv_cache_seq_rm(0, p0, p1)
                return True
        except Exception as exc:
            logger.debug("[LocalLlamaKVService] llm.kv_cache_seq_rm failed: %s", exc)

        ctx = getattr(self._llm, "_ctx", None)
        if ctx is not None:
            try:
                if hasattr(ctx, "kv_cache_seq_rm"):
                    ctx.kv_cache_seq_rm(0, p0, p1)
                    return True
            except Exception as exc:
                logger.debug("[LocalLlamaKVService] ctx.kv_cache_seq_rm failed: %s", exc)

        if self._llama_cpp_lib is not None and ctx is not None:
            raw_ctx = getattr(ctx, "ctx", None) or getattr(ctx, "_ctx", None)
            if raw_ctx is not None:
                try:
                    self._llama_cpp_lib.llama_kv_cache_seq_rm(raw_ctx, 0, p0, p1)
                    return True
                except Exception as exc:
                    logger.debug("[LocalLlamaKVService] raw llama_kv_cache_seq_rm failed: %s", exc)

        return False

    def _n_tokens(self) -> int:
        if self._llm is None:
            return 0
        if hasattr(self._llm, "n_tokens"):
            value = getattr(self._llm, "n_tokens")
            if isinstance(value, int):
                return value
        return int(getattr(self._llm, "_n_tokens", 0))

    def _set_n_tokens(self, value: int) -> None:
        if self._llm is None:
            return
        try:
            if hasattr(self._llm, "_n_tokens"):
                setattr(self._llm, "_n_tokens", value)
                return
            if hasattr(self._llm, "n_tokens"):
                setattr(self._llm, "n_tokens", value)
        except Exception:
            pass

    @staticmethod
    def _contains_stop(text: str) -> bool:
        return "<|user|>" in text or "</s>" in text

    @staticmethod
    def _trim_stop(text: str) -> str:
        for marker in ("<|user|>", "</s>"):
            idx = text.find(marker)
            if idx >= 0:
                text = text[:idx]
        return text

    @staticmethod
    def _load_config() -> LocalLlamaConfig:
        def _flag(name: str, default: bool = False) -> bool:
            raw = str(os.getenv(name, "1" if default else "0")).strip().lower()
            return raw in {"1", "true", "yes", "on"}

        def _int(name: str, default: int) -> int:
            raw = os.getenv(name)
            if raw is None:
                return default
            try:
                return int(raw)
            except ValueError:
                return default

        def _float(name: str, default: float) -> float:
            raw = os.getenv(name)
            if raw is None:
                return default
            try:
                return float(raw)
            except ValueError:
                return default

        cpu_threads = max(1, min((os.cpu_count() or 8) - 1, 12))
        return LocalLlamaConfig(
            enabled=_flag("TRACECAG_ENABLE_LOCAL_LLAMA_KV", False),
            model_path=os.getenv("TRACECAG_LOCAL_LLAMA_MODEL_PATH", ""),
            n_ctx=max(512, _int("TRACECAG_LOCAL_LLAMA_N_CTX", 2048)),
            n_batch=max(32, _int("TRACECAG_LOCAL_LLAMA_N_BATCH", 256)),
            n_threads=max(1, _int("TRACECAG_LOCAL_LLAMA_N_THREADS", cpu_threads)),
            n_threads_batch=max(1, _int("TRACECAG_LOCAL_LLAMA_N_THREADS_BATCH", cpu_threads)),
            max_tokens=max(16, _int("TRACECAG_LOCAL_LLAMA_MAX_TOKENS", 384)),
            temperature=max(0.0, min(1.5, _float("TRACECAG_LOCAL_LLAMA_TEMPERATURE", 0.7))),
            top_p=max(0.1, min(1.0, _float("TRACECAG_LOCAL_LLAMA_TOP_P", 0.9))),
            repeat_penalty=max(0.9, min(2.0, _float("TRACECAG_LOCAL_LLAMA_REPEAT_PENALTY", 1.1))),
            keep_session_ms=max(60000, _int("TRACECAG_LOCAL_LLAMA_KEEP_SESSION_MS", 600000)),
        )


_llama_kv_instance: Optional[LocalLlamaKVService] = None


def get_local_llama_kv_service() -> LocalLlamaKVService:
    global _llama_kv_instance
    if _llama_kv_instance is None:
        _llama_kv_instance = LocalLlamaKVService()
    return _llama_kv_instance
