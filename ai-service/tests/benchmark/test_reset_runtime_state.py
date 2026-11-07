from api.services.trace_cag.dependencies import dependency_record
from api.services.trace_cag.invalidation import observe_dependency_tokens, recheck_dependency_snapshot
from tracecag_bench.runtime.reset import reset_runtime_state


def test_reset_forgets_dependency_tokens(monkeypatch):
    monkeypatch.setenv("BENCHMARK_REDIS_DISABLED", "1")
    key = "learner:anonymous:profile"
    observe_dependency_tokens([dependency_record(key, "learner", "profile:B1", "request-profile")])

    ok, _ = recheck_dependency_snapshot([dependency_record(key, "learner", "profile:B2", "request-profile")])
    assert not ok

    reset_runtime_state()
    observe_dependency_tokens([dependency_record(key, "learner", "profile:B2", "request-profile")])
    ok, reasons = recheck_dependency_snapshot([dependency_record(key, "learner", "profile:B2", "request-profile")])
    assert ok, reasons
