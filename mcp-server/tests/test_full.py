"""
Comprehensive MCP Server Test Suite
Tests: server startup, all tools, Tavily live search, JSON-RPC protocol
"""

import asyncio
import json
import os
import subprocess
import sys
import time
from pathlib import Path

# ── Paths ────────────────────────────────────────────────────────────────────
MCP_ROOT = Path(__file__).parent.parent
REPO_ROOT = MCP_ROOT.parent
sys.path.insert(0, str(MCP_ROOT))
PASS = "✅ PASS"
FAIL = "❌ FAIL"
WARN = "⚠️  WARN"

results: list[dict] = []


def record(name: str, status: str, detail: str = "", duration_ms: float = 0):
    results.append({"name": name, "status": status, "detail": detail, "ms": duration_ms})
    tag = PASS if status == "pass" else (WARN if status == "warn" else FAIL)
    ms = f"  [{duration_ms:.0f}ms]" if duration_ms else ""
    print(f"  {tag}  {name}{ms}")
    if detail:
        for line in detail.splitlines():
            print(f"         {line}")


# ─────────────────────────────────────────────────────────────────────────────
# GROUP 1 — MCP Server Import & Boot
# ─────────────────────────────────────────────────────────────────────────────

def test_server_imports():
    print("\n【1】MCP Server — Module imports")
    t = time.perf_counter()

    failed = []
    try:
        import mcp
        record("mcp package", "pass", f"version: {getattr(mcp, '__version__', 'ok')}")
    except ImportError as e:
        record("mcp package", "fail", str(e))
        failed.append("mcp")

    for mod in ["httpx", "tavily", "yaml", "dotenv"]:
        try:
            __import__(mod)
            record(f"  package: {mod}", "pass")
        except ImportError as e:
            record(f"  package: {mod}", "fail", str(e))
            failed.append(mod)

    # Server module itself
    try:
        import server  # noqa: F401
        elapsed = (time.perf_counter() - t) * 1000
        record("server.py module load", "pass", duration_ms=elapsed)
    except Exception as e:
        record("server.py module load", "fail", str(e))
        failed.append("server")

    return len(failed) == 0


def test_json_rpc_handshake():
    """Send actual JSON-RPC initialize message via subprocess."""
    print("\n【2】MCP Server — JSON-RPC protocol handshake")

    python = str(MCP_ROOT / "venv" / "bin" / "python3.12")
    server_py = str(MCP_ROOT / "server.py")

    msg = json.dumps({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test-client", "version": "1.0"},
        },
    }) + "\n"

    t = time.perf_counter()
    try:
        proc = subprocess.Popen(
            [python, server_py],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={**os.environ, "PYTHONPATH": str(MCP_ROOT)},
        )
        stdout, stderr = proc.communicate(input=msg.encode(), timeout=8)
        elapsed = (time.perf_counter() - t) * 1000

        if stdout:
            try:
                resp = json.loads(stdout.strip().splitlines()[0])
                if resp.get("result", {}).get("serverInfo", {}).get("name") == "lexilingo-mcp":
                    record("initialize handshake", "pass",
                           f"serverInfo={resp['result']['serverInfo']}", elapsed)
                    return True
                else:
                    record("initialize handshake", "warn",
                           f"unexpected response: {json.dumps(resp)[:120]}", elapsed)
                    return False
            except json.JSONDecodeError:
                record("initialize handshake", "fail",
                       f"non-JSON stdout: {stdout[:200]}", elapsed)
                return False
        else:
            stderr_text = stderr.decode()[:300]
            record("initialize handshake", "fail",
                   f"no stdout. stderr: {stderr_text}", elapsed)
            return False
    except subprocess.TimeoutExpired:
        proc.kill()
        record("initialize handshake", "fail", "process timed out after 8s")
        return False
    except Exception as e:
        record("initialize handshake", "fail", str(e))
        return False


# ─────────────────────────────────────────────────────────────────────────────
# GROUP 2 — Tool: i18n_manager
# ─────────────────────────────────────────────────────────────────────────────

def test_i18n_manager():
    print("\n【3】Tool: manage_i18n_key")

    from tools.i18n_manager import manage_i18n_key

    i18n_dir = REPO_ROOT / "flutter-app" / "assets" / "i18n"
    if not i18n_dir.exists():
        record("i18n directory", "warn", f"Not found: {i18n_dir} — skipping write test")
        return

    record("i18n directory", "pass", str(i18n_dir))

    t = time.perf_counter()
    result = manage_i18n_key("__mcp_test__.hello_world", "Hello MCP World")
    elapsed = (time.perf_counter() - t) * 1000

    if result.get("success"):
        updated = [k for k, v in result["details"].items() if v in ("updated", "added_fallback")]
        record("write key across 7 langs", "pass",
               f"langs touched: {updated}", elapsed)
    else:
        record("write key across 7 langs", "fail", str(result))

    # Cleanup — remove test key
    import json as _json
    for lang in ["en", "vi", "ja", "ko", "zh", "fr", "es"]:
        fp = i18n_dir / f"{lang}.json"
        if fp.exists():
            data = _json.loads(fp.read_text())
            data.pop("__mcp_test__", None)
            fp.write_text(_json.dumps(data, ensure_ascii=False, indent=2))
    record("cleanup test key", "pass")


# ─────────────────────────────────────────────────────────────────────────────
# GROUP 3 — Tool: search_web (Tavily live)
# ─────────────────────────────────────────────────────────────────────────────

async def _run_tavily(query: str, depth: str = "basic", max_results: int = 3):
    from tools.web_search import search_web
    return await search_web(query=query, max_results=max_results, search_depth=depth)


def test_tavily_search():
    print("\n【4】Tool: search_web (Tavily live)")

    # Test 1 — basic search
    t = time.perf_counter()
    result = asyncio.run(_run_tavily("Flutter Dart latest stable version 2026"))
    elapsed = (time.perf_counter() - t) * 1000

    if "error" in result:
        record("basic search", "fail", result["error"], elapsed)
        return

    record("basic search — Flutter version",
           "pass" if result["total"] > 0 else "warn",
           f"results={result['total']}, answer={str(result.get('answer',''))[:80]}",
           elapsed)

    # Test 2 — language learning query
    t = time.perf_counter()
    result2 = asyncio.run(_run_tavily("IELTS Band 7 writing tips 2025 2026"))
    elapsed2 = (time.perf_counter() - t) * 1000

    record("basic search — IELTS query",
           "pass" if result2["total"] > 0 else "warn",
           f"results={result2['total']}, top_title={result2['results'][0]['title'][:60] if result2['results'] else 'none'}",
           elapsed2)

    # Test 3 — advanced depth
    t = time.perf_counter()
    result3 = asyncio.run(_run_tavily("LangGraph StateGraph tutorial", depth="advanced", max_results=2))
    elapsed3 = (time.perf_counter() - t) * 1000

    record("advanced search — LangGraph docs",
           "pass" if result3["total"] > 0 else "warn",
           f"results={result3['total']}, answer_len={len(str(result3.get('answer','')))}",
           elapsed3)

    # Test 4 — error handling: no API key
    old_key = os.environ.pop("TAVILY_API_KEY")
    result4 = asyncio.run(_run_tavily("test"))
    os.environ["TAVILY_API_KEY"] = old_key
    record("error handling — no API key",
           "pass" if "error" in result4 else "fail",
           result4.get("error", ""))

    # Test 5 — max_results clamping
    result5 = asyncio.run(_run_tavily("Python MCP protocol", max_results=99))
    record("max_results clamp to 10",
           "pass" if result5.get("total", 0) <= 10 else "fail",
           f"got {result5.get('total')} results")


# ─────────────────────────────────────────────────────────────────────────────
# GROUP 4 — Tool: get_backend_schema
# ─────────────────────────────────────────────────────────────────────────────

def test_backend_schema():
    print("\n【5】Tool: get_backend_schema")
    from tools.backend_schema import get_backend_schema

    # Full schema
    t = time.perf_counter()
    result = get_backend_schema()
    elapsed = (time.perf_counter() - t) * 1000

    total = result.get("total_endpoints", 0)
    tags = list(result.get("tags", {}).keys())

    if total >= 10:
        record("full schema scan", "pass",
               f"endpoints={total}, tags={len(tags)}: {', '.join(tags[:8])}...", elapsed)
    else:
        record("full schema scan", "fail", f"too few endpoints: {total}")

    # Filtered by /games
    result2 = get_backend_schema(filter_path="/games")
    game_eps = result2.get("total_endpoints", 0)
    record("filter /games",
           "pass" if game_eps > 0 else "warn",
           f"found {game_eps} game endpoints")

    # Filtered by /vocabulary
    result3 = get_backend_schema(filter_path="/vocabulary")
    vocab_eps = result3.get("total_endpoints", 0)
    record("filter /vocabulary",
           "pass" if vocab_eps > 0 else "warn",
           f"found {vocab_eps} vocabulary endpoints")

    # Sample endpoint shape
    sample_tag = tags[0] if tags else None
    if sample_tag:
        sample_eps = result["tags"][sample_tag][:2]
        record("endpoint shape check",
               "pass" if all("method" in e and "path" in e for e in sample_eps) else "fail",
               f"sample: {json.dumps(sample_eps, indent=2)}")


# ─────────────────────────────────────────────────────────────────────────────
# GROUP 5 — Tool: list_flutter_screens
# ─────────────────────────────────────────────────────────────────────────────

def test_flutter_screens():
    print("\n【6】Tool: list_flutter_screens")
    from tools.flutter_utils import list_flutter_screens

    # All screens
    t = time.perf_counter()
    result = list_flutter_screens()
    elapsed = (time.perf_counter() - t) * 1000

    total = result.get("total_screens", 0)
    features = list(result.get("by_feature", {}).keys())

    if total >= 10:
        record("full screen scan", "pass",
               f"screens={total}, features={features}", elapsed)
    else:
        record("full screen scan", "fail", f"too few screens: {total}")

    # Filter games
    result2 = list_flutter_screens(feature="games")
    game_screens = result2.get("total_screens", 0)
    game_list = [s["class"] for s in result2.get("by_feature", {}).get("games", [])]
    record("filter feature=games",
           "pass" if game_screens > 0 else "warn",
           f"{game_screens} screens: {game_list}")

    # Filter learning
    result3 = list_flutter_screens(feature="learning")
    record("filter feature=learning",
           "pass" if result3.get("total_screens", 0) > 0 else "warn",
           f"{result3.get('total_screens')} screens")

    # Screen shape
    for feature, screens in result.get("by_feature", {}).items():
        if screens:
            s = screens[0]
            ok = "class" in s and "file" in s
            record("screen shape check",
                   "pass" if ok else "fail",
                   f"sample: {json.dumps(s)}")
            break


# ─────────────────────────────────────────────────────────────────────────────
# GROUP 6 — LangGraph / LangChain (ai-service)
# ─────────────────────────────────────────────────────────────────────────────

def test_langgraph():
    print("\n【7】LangGraph / LangChain (ai-service)")

    ai_venv_python = str(REPO_ROOT / "ai-service" / "venv" / "bin" / "python3.12")
    ai_root = str(REPO_ROOT / "ai-service")

    if not Path(ai_venv_python).exists():
        record("ai-service venv", "warn", f"Not found: {ai_venv_python}")
        return

    record("ai-service venv", "pass", ai_venv_python)

    # Test 1: LangGraph + LangChain imports
    t = time.perf_counter()
    script = """
import sys
sys.path.insert(0, '.')
from langgraph.graph import StateGraph, END
from langchain_core.messages import HumanMessage
print('IMPORTS_OK')
"""
    r = subprocess.run(
        [ai_venv_python, "-c", script],
        capture_output=True, text=True, timeout=15,
        cwd=ai_root
    )
    elapsed = (time.perf_counter() - t) * 1000
    if "IMPORTS_OK" in r.stdout:
        record("langgraph + langchain-core imports", "pass",
               f"langgraph, langchain_core loaded", elapsed)
    else:
        record("langgraph + langchain-core imports", "fail",
               r.stderr[:200], elapsed)
        return

    # Test 2: TraceCAG state schema loads
    t = time.perf_counter()
    script2 = """
import sys
sys.path.insert(0, '.')
from api.services.trace_cag.state import TraceCAGState, create_initial_state
state = create_initial_state("test input", "session-123")
print(f'STATE_OK keys={len(state)}')
"""
    r2 = subprocess.run(
        [ai_venv_python, "-c", script2],
        capture_output=True, text=True, timeout=15,
        cwd=ai_root
    )
    elapsed2 = (time.perf_counter() - t) * 1000
    if "STATE_OK" in r2.stdout:
        record("TraceCAG StateSchema + create_initial_state", "pass",
               r2.stdout.strip(), elapsed2)
    else:
        record("TraceCAG StateSchema", "fail", r2.stderr[:200], elapsed2)

    # Test 3: Graph edges load (no model imports)
    t = time.perf_counter()
    script3 = """
import sys
sys.path.insert(0, '.')
from api.services.trace_cag.edges import (
    route_after_diagnosis, should_generate_tts,
    check_cache_hit, route_voice_or_text, should_analyze_pronunciation
)
print('EDGES_OK')
"""
    r3 = subprocess.run(
        [ai_venv_python, "-c", script3],
        capture_output=True, text=True, timeout=15,
        cwd=ai_root
    )
    elapsed3 = (time.perf_counter() - t) * 1000
    record("TraceCAG edges load",
           "pass" if "EDGES_OK" in r3.stdout else "fail",
           r3.stderr[:150] if "EDGES_OK" not in r3.stdout else "", elapsed3)

    # Test 4: DocumentIntelligenceService Tavily config
    t = time.perf_counter()
    script4 = f"""
import sys, os
sys.path.insert(0, '.')
# Only check the Tavily config, not the embedding service
import inspect
import ast, pathlib
src = pathlib.Path('api/services/document_intelligence.py').read_text()
has_tavily = 'api.tavily.com/search' in src or 'TAVILY_API_KEY' in src
print(f'TAVILY_CONFIG={{has_tavily}}')
"""
    r4 = subprocess.run(
        [ai_venv_python, "-c", script4],
        capture_output=True, text=True, timeout=10,
        cwd=ai_root
    )
    elapsed4 = (time.perf_counter() - t) * 1000
    if "TAVILY_CONFIG=True" in r4.stdout:
        record("DocumentIntelligenceService has Tavily config", "pass",
               "TAVILY_API_KEY + api.tavily.com/search found in source", elapsed4)
    else:
        record("DocumentIntelligenceService Tavily config", "fail",
               r4.stdout + r4.stderr[:100], elapsed4)

    # Test 5: LangGraph StateGraph can compile with dummy nodes
    t = time.perf_counter()
    script5 = """
import sys
sys.path.insert(0, '.')
from langgraph.graph import StateGraph, END
from typing import TypedDict

class TestState(TypedDict):
    value: str

def node_a(state):
    return {"value": state["value"] + "_A"}

def route(state):
    return "node_b" if "A" in state["value"] else "end"

graph = StateGraph(TestState)
graph.add_node("node_a", node_a)
graph.add_node("node_b", lambda s: {"value": s["value"] + "_B"})
graph.set_entry_point("node_a")
graph.add_conditional_edges("node_a", route, {"node_b": "node_b", "end": END})
graph.add_edge("node_b", END)
compiled = graph.compile()

import asyncio
result = asyncio.run(compiled.ainvoke({"value": "start"}))
print(f'GRAPH_OK value={result["value"]}')
"""
    r5 = subprocess.run(
        [ai_venv_python, "-c", script5],
        capture_output=True, text=True, timeout=15,
        cwd=ai_root
    )
    elapsed5 = (time.perf_counter() - t) * 1000
    if "GRAPH_OK" in r5.stdout:
        record("LangGraph StateGraph compile + ainvoke", "pass",
               r5.stdout.strip(), elapsed5)
    else:
        record("LangGraph StateGraph compile + ainvoke", "fail",
               r5.stderr[:200], elapsed5)


# ─────────────────────────────────────────────────────────────────────────────
# GROUP 7 — Integration: Tavily via MCP tool + LangChain tool wrapper
# ─────────────────────────────────────────────────────────────────────────────

def test_mcp_langgraph_integration():
    print("\n【8】Integration: MCP search_web → LangGraph node simulation")

    ai_venv_python = str(REPO_ROOT / "ai-service" / "venv" / "bin" / "python3.12")
    ai_root = str(REPO_ROOT / "ai-service")

    if not Path(ai_venv_python).exists():
        record("ai-service venv", "warn", "Not available, skipping integration test")
        return

    # Simulate: a LangGraph node calls MCP search_web via httpx
    # (represents how TraceCAG could call external tools via MCP)
    script = f"""
import sys, os, asyncio
sys.path.insert(0, '{str(MCP_ROOT)}')

# Simulate calling the MCP web_search tool function directly
# (same as how a LangChain tool wrapper would call it)
sys.path.insert(0, '{str(MCP_ROOT)}')
from tools.web_search import search_web

async def simulate_langgraph_node(state: dict) -> dict:
    '''Simulates a LangGraph retrieve_node that enriches context with web search.'''
    query = state.get('user_input', '')
    search_result = await search_web(query=query, max_results=3, search_depth='basic')

    web_snippets = [r['content'][:150] for r in search_result.get('results', [])]
    return {{
        **state,
        'web_context': web_snippets,
        'web_answer': search_result.get('answer', ''),
        'web_results_count': search_result.get('total', 0),
    }}

initial_state = {{
    'user_input': 'How do I use present perfect tense in English?',
    'session_id': 'test-integration-001',
}}

result = asyncio.run(simulate_langgraph_node(initial_state))
count = result['web_results_count']
answer = result.get('web_answer', '')[:80]
print(f'INTEGRATION_OK results={{count}} answer_preview={{answer}}')
"""
    t = time.perf_counter()
    r = subprocess.run(
        [ai_venv_python, "-c", script],
        capture_output=True, text=True, timeout=20,
    )
    elapsed = (time.perf_counter() - t) * 1000

    if "INTEGRATION_OK" in r.stdout:
        detail = r.stdout.strip().replace("INTEGRATION_OK ", "")
        record("MCP search_web callable from LangGraph node context", "pass",
               detail, elapsed)
    else:
        record("MCP search_web callable from LangGraph node context", "fail",
               r.stderr[:300], elapsed)

    # Test: LangGraph conditional edge after web search
    script2 = f"""
import sys, os, asyncio
sys.path.insert(0, '{str(MCP_ROOT)}')
from langgraph.graph import StateGraph, END
from typing import TypedDict, List
from tools.web_search import search_web

class SearchState(TypedDict):
    query: str
    web_results: List[str]
    enriched: bool

async def search_node(state: SearchState) -> SearchState:
    result = await search_web(state['query'], max_results=2)
    snippets = [r['content'][:100] for r in result.get('results', [])]
    return {{**state, 'web_results': snippets, 'enriched': len(snippets) > 0}}

def route_enriched(state: SearchState) -> str:
    return 'done' if state['enriched'] else 'fallback'

graph = StateGraph(SearchState)
graph.add_node('search', search_node)
graph.add_node('done', lambda s: s)
graph.add_node('fallback', lambda s: s)
graph.set_entry_point('search')
graph.add_conditional_edges('search', route_enriched, {{'done': 'done', 'fallback': 'fallback'}})
graph.add_edge('done', END)
graph.add_edge('fallback', END)
compiled = graph.compile()

result = asyncio.run(compiled.ainvoke({{'query': 'CEFR B2 vocabulary list', 'web_results': [], 'enriched': False}}))
ok = result.get('enriched', False)
count = len(result.get('web_results', []))
print(f'GRAPH_SEARCH_OK enriched={{ok}} snippets={{count}}')
"""
    t2 = time.perf_counter()
    r2 = subprocess.run(
        [ai_venv_python, "-c", script2],
        capture_output=True, text=True, timeout=25,
    )
    elapsed2 = (time.perf_counter() - t2) * 1000

    if "GRAPH_SEARCH_OK" in r2.stdout:
        detail = r2.stdout.strip().replace("GRAPH_SEARCH_OK ", "")
        record("LangGraph StateGraph with MCP search_web node", "pass",
               detail, elapsed2)
    else:
        record("LangGraph StateGraph with MCP search_web node", "fail",
               r2.stderr[:300], elapsed2)


# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

def print_summary():
    total = len(results)
    passed = sum(1 for r in results if r["status"] == "pass")
    warned = sum(1 for r in results if r["status"] == "warn")
    failed = sum(1 for r in results if r["status"] == "fail")
    total_ms = sum(r["ms"] for r in results)

    print("\n" + "═" * 60)
    print(f"  SUMMARY: {passed}/{total} passed  |  {warned} warnings  |  {failed} failed")
    print(f"  Total time: {total_ms:.0f}ms")
    print("═" * 60)

    if failed > 0:
        print("\nFailed tests:")
        for r in results:
            if r["status"] == "fail":
                print(f"  ❌ {r['name']}: {r['detail'][:80]}")

    if warned > 0:
        print("\nWarnings:")
        for r in results:
            if r["status"] == "warn":
                print(f"  ⚠️  {r['name']}: {r['detail'][:80]}")


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 60)
    print("  LexiLingo MCP Server — Full Test Suite")
    print("=" * 60)

    os.chdir(MCP_ROOT)  # ensure relative imports resolve

    test_server_imports()
    test_json_rpc_handshake()
    test_i18n_manager()
    test_tavily_search()
    test_backend_schema()
    test_flutter_screens()
    test_langgraph()
    test_mcp_langgraph_integration()
    print_summary()

    failed_count = sum(1 for r in results if r["status"] == "fail")
    sys.exit(0 if failed_count == 0 else 1)
