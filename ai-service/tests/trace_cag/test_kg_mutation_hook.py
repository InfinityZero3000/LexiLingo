"""A KG content change must detach the artifacts that were built from it.

Without the publisher, the new content token only ever reached
`observe_dependency_tokens`, which is `setdefault` by design so a stale artifact
cannot roll a token back. The store therefore kept the first version forever,
`recheck_dependency_snapshot` compared a stale entry against its own token,
matched, and L0 served the pre-change answer. The certificate cannot catch this
either: its `kg_version` is the hardcoded schema constant, not the content hash.
"""

import pytest

from api.services.trace_cag.dependencies import dependency_record
from api.services.trace_cag.invalidation import (
    clear_reverse_index,
    observe_dependency_tokens,
    recheck_dependency_snapshot,
    register_reverse_edges,
    set_dependency_token,
)

KG_KEY = "kg:tracecag:main"


@pytest.fixture(autouse=True)
def _clean():
    clear_reverse_index()
    yield
    clear_reverse_index()


def _entry_deps(version):
    return [dependency_record(KG_KEY, "kg", version, "kuzu")]


def test_stale_entry_survives_without_the_publisher():
    """Documents the defect: observing a new token is not publishing it."""
    deps = _entry_deps("kg_content_vAAA")
    observe_dependency_tokens(deps)
    register_reverse_edges("artifact-1", deps)

    observe_dependency_tokens(_entry_deps("kg_content_vBBB"))

    assert recheck_dependency_snapshot(deps)[0] is True


def test_publisher_detaches_and_blocks_the_stale_entry():
    deps = _entry_deps("kg_content_vAAA")
    observe_dependency_tokens(deps)
    register_reverse_edges("artifact-1", deps)

    assert set_dependency_token(KG_KEY, "kg_content_vBBB") == {"artifact-1"}

    ok, reasons = recheck_dependency_snapshot(deps)
    assert ok is False
    assert f"snapshot_changed_before_serve:{KG_KEY}" in reasons


def test_unchanged_content_keeps_serving():
    deps = _entry_deps("kg_content_vAAA")
    observe_dependency_tokens(deps)
    register_reverse_edges("artifact-1", deps)

    set_dependency_token(KG_KEY, "kg_content_vAAA")

    assert recheck_dependency_snapshot(deps)[0] is True
