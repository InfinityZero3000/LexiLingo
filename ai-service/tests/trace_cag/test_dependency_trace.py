import pytest

from api.services.trace_cag.dependencies import DependencyEvent, compile_dependency_trace


def test_compile_dependency_trace_deduplicates_and_sorts():
    events = [
        DependencyEvent("policy:tutor", "policy", "v2", "prompt-registry"),
        DependencyEvent("learner:u1:profile", "learner", "7", "learner-state"),
        DependencyEvent("policy:tutor", "policy", "v2", "prompt-registry"),
    ]

    assert compile_dependency_trace(events) == (
        DependencyEvent("learner:u1:profile", "learner", "7", "learner-state"),
        DependencyEvent("policy:tutor", "policy", "v2", "prompt-registry"),
    )


def test_compile_dependency_trace_rejects_conflicting_versions():
    with pytest.raises(ValueError, match="conflicting dependency versions"):
        compile_dependency_trace([
            DependencyEvent("kg:main", "kg", "v1", "kuzu"),
            DependencyEvent("kg:main", "kg", "v2", "kuzu"),
        ])


def test_compile_dependency_trace_rejects_missing_required_token():
    with pytest.raises(ValueError, match="missing required dependency token"):
        compile_dependency_trace([
            DependencyEvent("source:qa", "source", "", "dataset", required=True),
        ])


def test_compile_dependency_trace_allows_missing_optional_token():
    assert compile_dependency_trace([
        DependencyEvent("source:optional", "source", "", "dataset", required=False),
    ]) == (
        DependencyEvent("source:optional", "source", "", "dataset", required=False),
    )
