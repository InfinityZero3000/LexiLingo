# TraceCAG Architecture Audit - 2026-05-30

Scope: audit kiến trúc, technical debt, logic, setup và rủi ro vận hành của TraceCAG trong `ai-service`.

Nguồn kiểm tra:
- Static code review: `api/services/trace_cag/*`, orchestrator, routes, config, Redis/KG/model gateway.
- Code graph: full build trên repo LexiLingo, 939 files, 9557 nodes, 67577 edges.
- Verification commands:
  - `python3 -m compileall api/services/trace_cag` - pass.
  - `DEBUG=false venv/bin/python -m pytest tests/trace_cag -q` - 85 passed, 300 warnings, 745.37s.
  - `python3 -m pytest tests/trace_cag/test_edges_routing.py -q` - fail nếu không override `DEBUG=false` do shell env `DEBUG=release`.
  - L1 cache near-hit reproducer - fail runtime tại `nodes_v2.py:1475`.

## Executive Summary

TraceCAG có hướng kiến trúc đúng: LangGraph StateGraph, cache gate trước LLM, KG + diagnosis chạy song song, retrieval có ngân sách, generation có fallback, và response contract khá rõ. Tuy nhiên hiện trạng code đang có risk mức Medium-High vì logic quan trọng nằm trong `nodes_v2.py` quá lớn, nhiều dependency vận hành được gọi trực tiếp trên critical path, và có một bug runtime cụ thể trong L1 cache near-hit.

Kết luận của architect: nên giữ topology hiện tại, nhưng cần tách module và sửa các guard vận hành trước khi coi TraceCAG là stable production core. Ưu tiên cao nhất là cache L1 crash, Redis fail-fast, config env collision, và test coverage cho cache gate.

## Architecture Map

Core files:
- `api/services/trace_cag/graph.py` - build LangGraph, singleton `TraceCAGPipeline`, format response.
- `api/services/trace_cag/nodes_v2.py` - toàn bộ node runtime và nhiều algorithm phụ: cache, adaptive, retrieval, provider calls, benchmark, STT/TTS/pronunciation.
- `api/services/trace_cag/edges.py` - conditional routing.
- `api/services/trace_cag/state.py` - `TraceCAGState` TypedDict contract.
- `api/services/trace_cag/retrieval_ranker.py` - online pairwise ranker in-process.
- `api/services/orchestrator.py` - lifecycle facade cho chat/lexi/topic flows.

Entrypoints:
- `/api/v1/ai/trace-cag/analyze` gọi trực tiếp `get_trace_cag().analyze()`.
- `/api/v1/chat/messages`, Lexi chat, Topic chat gọi `get_orchestrator().process()`.
- Dual-stream orchestrator lazy-load TraceCAG trực tiếp.
- `/visualizer` phục vụ `static/trace-cag-node-viz.html`.

Runtime topology hiện tại:

```text
input_node
  -> stt_node? -> cache_gate_node
  -> cache hit: END
  -> cache miss: kg_diagnose_node
       -> asyncio.gather(kg_expand_node, diagnose_node, _jit_graph_extract_node)
  -> route_after_diagnosis
       -> ask_clarify_node -> END
       -> vietnamese_node -> retrieve_node
       -> retrieve_node
  -> generate_node
  -> pronunciation_node? -> END