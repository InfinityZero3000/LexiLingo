#!/usr/bin/env python3
"""
JIT Mini-Graph + Implicit KG Routing + KV Cache Optimization (CPU-only).

This script demonstrates a production-oriented Cache-Augmented Generation pipeline:
1) Sub-100ms JIT entity extraction with GLiNER
2) Lightweight in-memory mini-graph assembly with NetworkX
3) Compact graph serialization for a "Soft Graph Prompt"
4) llama-cpp-python inference on x86 CPU with explicit KV cache segment eviction

Recommended install:
  pip install gliner networkx llama-cpp-python

Example:
  python jit_graph_cag_cpu.py \
    --model-path ./models/your-model.Q4_K_M.gguf \
    --query "Explain why Tesla partnered with Panasonic for battery supply in Nevada."
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
import time
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import networkx as nx

try:
    from gliner import GLiNER
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "Missing dependency: gliner. Install with: pip install gliner"
    ) from exc

try:
    from llama_cpp import Llama
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "Missing dependency: llama-cpp-python. Install with: pip install llama-cpp-python"
    ) from exc

try:
    from llama_cpp import llama_cpp as llama_cpp_lib
except Exception:  # pragma: no cover
    llama_cpp_lib = None


LOGGER = logging.getLogger("jit_graph_cag")


@dataclass
class ExtractedEntity:
    text: str
    label: str
    score: float
    start: int
    end: int


@dataclass
class RuntimeConfig:
    model_path: str
    gliner_model: str = "urchade/gliner_small-v2.1"
    n_ctx: int = 2048
    n_batch: int = 256
    n_threads: int = max(1, min((os.cpu_count() or 8) - 1, 12))
    n_threads_batch: int = max(1, min((os.cpu_count() or 8) - 1, 12))
    max_graph_nodes: int = 10
    max_graph_edges: int = 14
    max_graph_chars: int = 1400
    extraction_target_ms: float = 100.0
    generation_max_tokens: int = 256
    temperature: float = 0.2
    top_p: float = 0.9
    repeat_penalty: float = 1.1
    seq_id: int = 0


class JITMiniGraphExtractor:
    """Fast, local, non-LLM entity extraction + relation heuristics."""

    DEFAULT_LABELS: Tuple[str, ...] = (
        "person",
        "organization",
        "location",
        "event",
        "product",
        "technology",
        "date",
        "time",
        "law",
        "financial_term",
    )

    def __init__(
        self,
        model_name: str,
        labels: Optional[Sequence[str]] = None,
        threshold: float = 0.45,
        max_nodes: int = 10,
        max_edges: int = 14,
    ) -> None:
        self.labels = tuple(labels) if labels else self.DEFAULT_LABELS
        self.threshold = threshold
        self.max_nodes = max_nodes
        self.max_edges = max_edges
        self.model = GLiNER.from_pretrained(model_name)

    def extract(self, text: str) -> Tuple[nx.DiGraph, Dict[str, Any], float]:
        t0 = time.perf_counter()
        raw_entities = self.model.predict_entities(text, labels=list(self.labels), threshold=self.threshold)
        entities = self._normalize_entities(raw_entities, text)
        entities = self._dedupe_entities(entities)[: self.max_nodes]
        graph = self._build_graph(text, entities)
        graph_payload = self._graph_to_payload(graph)
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        return graph, graph_payload, elapsed_ms

    def _normalize_entities(self, raw_entities: Any, text: str) -> List[ExtractedEntity]:
        normalized: List[ExtractedEntity] = []
        if not isinstance(raw_entities, list):
            return normalized

        for item in raw_entities:
            if not isinstance(item, dict):
                continue
            entity_text = str(item.get("text") or "").strip()
            if not entity_text:
                continue
            label = str(item.get("label") or "entity").strip().lower()
            score = float(item.get("score") or 0.0)
            start = item.get("start")
            end = item.get("end")

            if not isinstance(start, int) or not isinstance(end, int) or start < 0 or end <= start:
                probe = text.lower().find(entity_text.lower())
                if probe < 0:
                    continue
                start = probe
                end = probe + len(entity_text)

            normalized.append(
                ExtractedEntity(
                    text=entity_text,
                    label=label,
                    score=max(0.0, min(1.0, score)),
                    start=start,
                    end=end,
                )
            )

        return sorted(normalized, key=lambda e: (e.start, -e.score, e.end))

    def _dedupe_entities(self, entities: Sequence[ExtractedEntity]) -> List[ExtractedEntity]:
        deduped: List[ExtractedEntity] = []
        seen = set()
        for ent in entities:
            key = (ent.text.lower(), ent.label)
            if key in seen:
                continue
            seen.add(key)
            deduped.append(ent)
        return deduped

    def _build_graph(self, text: str, entities: Sequence[ExtractedEntity]) -> nx.DiGraph:
        graph = nx.DiGraph()

        node_ids: List[str] = []
        for idx, ent in enumerate(entities):
            node_id = f"e{idx}"
            node_ids.append(node_id)
            graph.add_node(
                node_id,
                t=ent.text,
                l=ent.label,
                s=round(ent.score, 3),
                b=ent.start,
                e=ent.end,
            )

        # Heuristic relation extraction: adjacent entities + local span phrase.
        edge_count = 0
        for i in range(len(entities) - 1):
            if edge_count >= self.max_edges:
                break
            left = entities[i]
            right = entities[i + 1]
            between = text[left.end : right.start]
            relation = self._infer_relation_phrase(between)
            graph.add_edge(
                node_ids[i],
                node_ids[i + 1],
                r=relation,
                s=round(max(0.05, min(left.score, right.score)), 3),
                d=max(0, right.start - left.end),
            )
            edge_count += 1

        return graph

    @staticmethod
    def _infer_relation_phrase(span_text: str) -> str:
        compact = re.sub(r"\s+", " ", span_text).strip(" ,.;:\n\t")
        if not compact:
            return "related_to"
        if len(compact) > 34:
            return "contextual_link"
        if re.search(r"\b(in|on|at|from|to|with|for|by|of|during)\b", compact, flags=re.IGNORECASE):
            return compact.lower()
        if re.search(r"\b(causes|drives|owns|acquired|built|founded|supports|supplies)\b", compact, flags=re.IGNORECASE):
            return compact.lower()
        return "related_to"

    def _graph_to_payload(self, graph: nx.DiGraph) -> Dict[str, Any]:
        nodes = []
        for node_id, attrs in graph.nodes(data=True):
            nodes.append(
                {
                    "id": node_id,
                    "t": attrs.get("t", ""),
                    "l": attrs.get("l", "entity"),
                    "s": attrs.get("s", 0.0),
                }
            )

        edges = []
        for src, dst, attrs in graph.edges(data=True):
            edges.append(
                {
                    "u": src,
                    "v": dst,
                    "r": attrs.get("r", "related_to"),
                    "s": attrs.get("s", 0.0),
                }
            )

        return {
            "v": 1,
            "n": nodes,
            "e": edges,
        }


class LlamaImplicitGraphRouter:
    """
    CPU-first llama-cpp runtime with explicit KV cache range eviction.

    Memory policy:
    - Pin core system context in KV cache.
    - Append per-query JIT graph + raw user query.
    - Generate answer.
    - Remove only [turn_start, turn_end) tokens from KV cache.

    This preserves always-on system instructions while reclaiming transient
    graph/query memory to avoid RAM growth and OOM on 16-32GB systems.
    """

    def __init__(self, cfg: RuntimeConfig, system_prompt: str) -> None:
        if not os.path.exists(cfg.model_path):
            raise FileNotFoundError(
                f"Model not found at '{cfg.model_path}'. "
                "Place your Q4_K_M GGUF model and re-run."
            )

        self.cfg = cfg
        self.system_prompt = system_prompt.strip()
        self.llm = Llama(
            model_path=cfg.model_path,
            n_ctx=cfg.n_ctx,
            n_batch=cfg.n_batch,
            n_threads=cfg.n_threads,
            n_threads_batch=cfg.n_threads_batch,
            n_gpu_layers=0,
            f16_kv=True,
            use_mmap=True,
            use_mlock=False,
            logits_all=False,
            embedding=False,
            verbose=False,
        )
        self.pinned_token_count = 0
        self._pin_core_context()
        self._log_kv_memory_hint()

    def answer(self, query: str, soft_graph: str) -> str:
        turn_prompt = self._format_turn_prompt(query=query, soft_graph=soft_graph)
        turn_tokens = self.llm.tokenize(turn_prompt.encode("utf-8"), add_bos=False)

        self._ensure_context_room(len(turn_tokens), self.cfg.generation_max_tokens)

        turn_start = self._n_tokens()
        output_tokens: List[int] = []
        text_chunks: List[str] = []

        generator = self.llm.generate(
            turn_tokens,
            top_k=40,
            top_p=self.cfg.top_p,
            temp=self.cfg.temperature,
            repeat_penalty=self.cfg.repeat_penalty,
            reset=False,
        )

        for token in generator:
            output_tokens.append(token)
            piece = self.llm.detokenize([token]).decode("utf-8", errors="ignore")
            text_chunks.append(piece)

            if len(output_tokens) >= self.cfg.generation_max_tokens:
                break
            if self._contains_stop("".join(text_chunks)):
                break

        answer_text = self._trim_stop("".join(text_chunks)).strip()
        turn_end = self._n_tokens()

        # Critical memory action: evict only this turn's transient segment.
        self._evict_turn_segment(turn_start, turn_end)
        return answer_text

    def _pin_core_context(self) -> None:
        self.llm.reset()
        core_prompt = (
            "<|system|>\n"
            f"{self.system_prompt}\n"
            "Rules: prioritize factual grounding from SOFT_GRAPH_JIT, be concise, and state uncertainty when evidence is weak.\n"
            "<|assistant|>\n"
        )
        core_tokens = self.llm.tokenize(core_prompt.encode("utf-8"), add_bos=True)
        self.llm.eval(core_tokens)
        self.pinned_token_count = self._n_tokens()

    def _format_turn_prompt(self, query: str, soft_graph: str) -> str:
        return (
            "<|user|>\n"
            "SOFT_GRAPH_JIT(JSON, compressed):\n"
            f"{soft_graph}\n"
            "RAW_QUERY:\n"
            f"{query}\n"
            "Return a grounded answer.\n"
            "<|assistant|>\n"
        )

    def _ensure_context_room(self, incoming_tokens: int, reserve_gen_tokens: int) -> None:
        projected = self._n_tokens() + incoming_tokens + reserve_gen_tokens
        if projected >= self.cfg.n_ctx:
            LOGGER.warning(
                "Context near limit (%d/%d). Re-pinning core context.",
                projected,
                self.cfg.n_ctx,
            )
            self._pin_core_context()

    def _evict_turn_segment(self, start_pos: int, end_pos: int) -> None:
        if end_pos <= start_pos:
            return

        removed = self._kv_cache_seq_rm(self.cfg.seq_id, start_pos, end_pos)
        if removed:
            self._set_n_tokens(self.pinned_token_count)
            return

        # Fallback for older bindings: hard reset and re-pin core context.
        LOGGER.warning(
            "KV eviction API not available in this llama-cpp-python version. "
            "Falling back to reset+repin."
        )
        self._pin_core_context()

    def _kv_cache_seq_rm(self, seq_id: int, p0: int, p1: int) -> bool:
        try:
            if hasattr(self.llm, "kv_cache_seq_rm"):
                self.llm.kv_cache_seq_rm(seq_id, p0, p1)
                return True
        except Exception as exc:
            LOGGER.debug("llm.kv_cache_seq_rm failed: %s", exc)

        ctx = getattr(self.llm, "_ctx", None)
        if ctx is not None:
            try:
                if hasattr(ctx, "kv_cache_seq_rm"):
                    ctx.kv_cache_seq_rm(seq_id, p0, p1)
                    return True
            except Exception as exc:
                LOGGER.debug("ctx.kv_cache_seq_rm failed: %s", exc)

        if llama_cpp_lib is not None:
            raw_ctx = None
            if ctx is not None:
                raw_ctx = getattr(ctx, "ctx", None) or getattr(ctx, "_ctx", None)
            if raw_ctx is not None:
                try:
                    llama_cpp_lib.llama_kv_cache_seq_rm(raw_ctx, seq_id, p0, p1)
                    return True
                except Exception as exc:
                    LOGGER.debug("llama_cpp.llama_kv_cache_seq_rm failed: %s", exc)

        return False

    def _n_tokens(self) -> int:
        if hasattr(self.llm, "n_tokens"):
            value = getattr(self.llm, "n_tokens")
            if isinstance(value, int):
                return value
        return int(getattr(self.llm, "_n_tokens", 0))

    def _set_n_tokens(self, value: int) -> None:
        try:
            if hasattr(self.llm, "_n_tokens"):
                setattr(self.llm, "_n_tokens", value)
                return
            if hasattr(self.llm, "n_tokens"):
                setattr(self.llm, "n_tokens", value)
                return
        except Exception:
            pass

        # If token pointer cannot be set, re-pin to keep consistent state.
        self._pin_core_context()

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

    def _log_kv_memory_hint(self) -> None:
        # Rough hint only. Exact KV size depends on model internals and backend.
        meta = getattr(self.llm, "metadata", {}) or {}
        n_layer = int(meta.get("llama.block_count", meta.get("llama.n_layer", 0)) or 0)
        n_embd = int(meta.get("llama.embedding_length", meta.get("llama.n_embd", 0)) or 0)
        if n_layer <= 0 or n_embd <= 0:
            LOGGER.info("Loaded model with n_ctx=%d (KV size hint unavailable).", self.cfg.n_ctx)
            return

        # Approx: K + V in fp16 => 2 tensors * 2 bytes each.
        approx_kv_bytes = self.cfg.n_ctx * n_layer * n_embd * 4
        approx_gb = approx_kv_bytes / (1024 ** 3)
        LOGGER.info(
            "Approx KV cache memory at n_ctx=%d: %.2f GB (estimate).",
            self.cfg.n_ctx,
            approx_gb,
        )


class JITGraphCAGPipeline:
    def __init__(self, cfg: RuntimeConfig) -> None:
        self.cfg = cfg
        self.extractor = JITMiniGraphExtractor(
            model_name=cfg.gliner_model,
            max_nodes=cfg.max_graph_nodes,
            max_edges=cfg.max_graph_edges,
        )
        self.router = LlamaImplicitGraphRouter(
            cfg=cfg,
            system_prompt=(
                "You are a precise technical assistant. "
                "Use SOFT_GRAPH_JIT as structural guidance and ground claims to it when possible."
            ),
        )

    def process_query(self, query: str) -> Dict[str, Any]:
        graph, payload, extraction_ms = self.extractor.extract(query)
        soft_graph = self.serialize_soft_graph(payload, self.cfg.max_graph_chars)
        answer = self.router.answer(query=query, soft_graph=soft_graph)

        warning = None
        if extraction_ms > self.cfg.extraction_target_ms:
            warning = (
                f"Extraction latency {extraction_ms:.2f}ms exceeds target "
                f"{self.cfg.extraction_target_ms:.2f}ms"
            )

        return {
            "query": query,
            "answer": answer,
            "soft_graph": soft_graph,
            "entity_count": graph.number_of_nodes(),
            "edge_count": graph.number_of_edges(),
            "extraction_ms": round(extraction_ms, 2),
            "warning": warning,
        }

    @staticmethod
    def serialize_soft_graph(payload: Dict[str, Any], max_chars: int) -> str:
        compact = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
        if len(compact) <= max_chars:
            return compact

        # Progressive truncation strategy: remove edges first, then trim nodes.
        shrunk = {
            "v": payload.get("v", 1),
            "n": list(payload.get("n", [])),
            "e": list(payload.get("e", [])),
        }

        while len(json.dumps(shrunk, separators=(",", ":"), ensure_ascii=False)) > max_chars and shrunk["e"]:
            shrunk["e"].pop()

        while len(json.dumps(shrunk, separators=(",", ":"), ensure_ascii=False)) > max_chars and len(shrunk["n"]) > 2:
            shrunk["n"].pop()

        return json.dumps(shrunk, separators=(",", ":"), ensure_ascii=False)


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="JIT Mini-Graph CAG with llama-cpp KV optimization")
    parser.add_argument("--model-path", required=True, help="Path to quantized GGUF model (Q4_K_M recommended)")
    parser.add_argument("--gliner-model", default="urchade/gliner_small-v2.1", help="GLiNER model name")
    parser.add_argument("--query", default="", help="Single query. If empty, run interactive mode.")
    parser.add_argument("--n-ctx", type=int, default=2048, help="Context window. Keep low for RAM safety.")
    parser.add_argument("--n-batch", type=int, default=256, help="Batch size for llama-cpp eval")
    parser.add_argument("--n-threads", type=int, default=max(1, min((os.cpu_count() or 8) - 1, 12)))
    parser.add_argument("--max-graph-nodes", type=int, default=10)
    parser.add_argument("--max-graph-edges", type=int, default=14)
    parser.add_argument("--max-graph-chars", type=int, default=1400)
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args(argv)


def build_config(args: argparse.Namespace) -> RuntimeConfig:
    return RuntimeConfig(
        model_path=args.model_path,
        gliner_model=args.gliner_model,
        n_ctx=max(512, args.n_ctx),
        n_batch=max(32, args.n_batch),
        n_threads=max(1, args.n_threads),
        n_threads_batch=max(1, args.n_threads),
        max_graph_nodes=max(2, args.max_graph_nodes),
        max_graph_edges=max(1, args.max_graph_edges),
        max_graph_chars=max(300, args.max_graph_chars),
    )


def run_once(pipeline: JITGraphCAGPipeline, query: str) -> None:
    result = pipeline.process_query(query)
    print("\n=== RESULT ===")
    print(f"Query: {result['query']}")
    print(f"Extraction: {result['extraction_ms']} ms")
    print(f"Mini-Graph: {result['entity_count']} nodes, {result['edge_count']} edges")
    print(f"SoftGraph JSON: {result['soft_graph']}")
    print("Answer:")
    print(result["answer"])
    if result.get("warning"):
        print(f"Warning: {result['warning']}")


def run_interactive(pipeline: JITGraphCAGPipeline) -> None:
    print("Interactive mode. Type 'exit' to stop.")
    while True:
        try:
            query = input("\nquery> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nBye")
            return
        if not query:
            continue
        if query.lower() in {"exit", "quit"}:
            print("Bye")
            return
        run_once(pipeline, query)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    )

    cfg = build_config(args)
    pipeline = JITGraphCAGPipeline(cfg)

    if args.query:
        run_once(pipeline, args.query)
    else:
        run_interactive(pipeline)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
