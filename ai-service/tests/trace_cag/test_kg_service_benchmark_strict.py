import pytest

from api.services import kg_service_v3 as kg_module


def test_strict_snapshot_mode_does_not_rebuild_after_open_failure(monkeypatch, tmp_path):
    snapshot = tmp_path / "working.db"
    snapshot.write_bytes(b"invalid")
    monkeypatch.setattr(kg_module.settings, "KUZU_DB_PATH", str(snapshot))
    monkeypatch.setenv("TRACECAG_KG_STRICT_SNAPSHOT", "true")
    monkeypatch.setattr(kg_module.kuzu, "Database", lambda _path: (_ for _ in ()).throw(RuntimeError("open failed")))
    rebuilt = []
    monkeypatch.setattr(kg_module.KnowledgeGraphServiceV3, "_hard_rebuild_db", lambda *_args, **_kwargs: rebuilt.append(True))

    with pytest.raises(RuntimeError, match="open failed"):
        kg_module.KnowledgeGraphServiceV3()

    assert rebuilt == []


def test_strict_snapshot_mode_rejects_empty_graph_instead_of_seeding(monkeypatch, tmp_path):
    snapshot = tmp_path / "working.db"
    snapshot.write_bytes(b"placeholder")
    monkeypatch.setattr(kg_module.settings, "KUZU_DB_PATH", str(snapshot))
    monkeypatch.setenv("TRACECAG_KG_STRICT_SNAPSHOT", "true")
    monkeypatch.setattr(kg_module.kuzu, "Database", lambda _path: object())
    monkeypatch.setattr(kg_module.kuzu, "Connection", lambda _db: object())
    monkeypatch.setattr(kg_module.KnowledgeGraphServiceV3, "_ensure_schema", lambda _self: None)
    monkeypatch.setattr(kg_module.KnowledgeGraphServiceV3, "get_concept_count", lambda _self: 0)
    seeded = []
    monkeypatch.setattr(kg_module.KnowledgeGraphServiceV3, "_seed_default_graph", lambda _self: seeded.append(True))

    with pytest.raises(RuntimeError, match="empty"):
        kg_module.KnowledgeGraphServiceV3()

    assert seeded == []
