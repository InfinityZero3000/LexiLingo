from api.services.trace_cag.invalidation import (
    clear_reverse_index,
    observe_dependency_tokens,
    recheck_dependency_snapshot,
    register_reverse_edges,
    set_dependency_token,
)


DEPENDENCY = {
    "key": "learner:u1:profile",
    "kind": "learner",
    "version": "7",
    "provenance": "learner-state",
    "required": True,
}


def setup_function():
    clear_reverse_index()


def test_unchanged_snapshot_passes_recheck():
    observe_dependency_tokens([DEPENDENCY])

    assert recheck_dependency_snapshot([DEPENDENCY]) == (True, ())


def test_mutation_between_validation_and_serve_fails_closed():
    observe_dependency_tokens([DEPENDENCY])
    register_reverse_edges("artifact-1", [DEPENDENCY])

    invalidated = set_dependency_token("learner:u1:profile", "8")
    passed, reasons = recheck_dependency_snapshot([DEPENDENCY])

    assert invalidated == {"artifact-1"}
    assert passed is False
    assert reasons == ("snapshot_changed_before_serve:learner:u1:profile",)


def test_missing_required_token_fails_closed():
    assert recheck_dependency_snapshot([DEPENDENCY]) == (
        False,
        ("dependency_token_unavailable:learner:u1:profile",),
    )


def test_optional_missing_token_does_not_block_service():
    optional = {**DEPENDENCY, "required": False}
    assert recheck_dependency_snapshot([optional]) == (True, ())
