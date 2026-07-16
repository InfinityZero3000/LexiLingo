from api.services.trace_cag.dependencies import (
    POLICY_VERSION_TOKEN,
    dependency_record,
    stable_version_token,
)
from api.services.trace_cag.generate import _state_with_policy_dependency


def test_stable_version_token_is_order_independent():
    assert stable_version_token({"a": 1, "b": 2}, prefix="state") == stable_version_token(
        {"b": 2, "a": 1}, prefix="state"
    )


def test_generation_read_adds_explicit_policy_dependency():
    state = {"dependency_events": [dependency_record("kg:main", "kg", "v1", "kuzu")]}

    enriched = _state_with_policy_dependency(state)

    assert state["dependency_events"] == [dependency_record("kg:main", "kg", "v1", "kuzu")]
    assert enriched["dependency_events"][-1] == dependency_record(
        "policy:tracecag:generation",
        "policy",
        POLICY_VERSION_TOKEN,
        "generation-policy",
    )
