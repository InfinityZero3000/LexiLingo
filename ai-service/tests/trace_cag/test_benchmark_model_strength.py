"""Regression test for benchmark model-strength classification (Bug 9).

The old substring-tag logic mis-read "groq/qwen/qwen3-32b" as WEAK and
"qwen3-1.7b" as STRONG ("7b" ⊂ "1.7b") — exactly backwards — so the main
32B benchmark model got the aggressive extractive override of its answers.
"""

from api.services.trace_cag.benchmark.qa_generation import _is_strong_benchmark_model


def test_qwen3_32b_is_strong():
    assert _is_strong_benchmark_model("groq/qwen/qwen3-32b") is True


def test_qwen3_1_7b_is_weak():
    # "7b" is a substring of "1.7b" — must NOT classify the 1.7B model as strong.
    assert _is_strong_benchmark_model("ollama/lexilingo-qwen3-1.7b") is False


def test_cloud_models_are_strong():
    assert _is_strong_benchmark_model("gemini-2.0-flash") is True


def test_small_instant_model_is_weak():
    assert _is_strong_benchmark_model("groq/llama-3.1-8b-instant") is False


def test_large_llama_is_strong():
    assert _is_strong_benchmark_model("groq/llama-3.1-70b-versatile") is True


def test_extractive_paths_never_strong():
    assert _is_strong_benchmark_model("extractive_fallback") is False
    assert _is_strong_benchmark_model("extractive_policy") is False


def test_empty_model_is_weak():
    assert _is_strong_benchmark_model("") is False
