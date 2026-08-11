from pathlib import Path
import sys

import pytest

from scripts import rebuild_runtime_kg as rebuild


def test_dry_run_reports_paths_without_rebuilding(tmp_path, monkeypatch, capsys):
    root = tmp_path / "ai-service"
    target = root / "data" / "runtime.kuzu"
    target.parent.mkdir(parents=True)
    monkeypatch.setattr(rebuild, "AI_SERVICE_ROOT", root)
    monkeypatch.setattr(sys, "argv", ["rebuild_runtime_kg.py", "--target", str(target), "--dry-run"])
    monkeypatch.setattr(rebuild, "rebuild", lambda *_args: pytest.fail("dry-run rebuilt the KG"))

    rebuild.main()

    assert f"source={target}" in capsys.readouterr().out


def test_validate_target_refuses_broad_or_nested_paths(tmp_path, monkeypatch):
    root = tmp_path / "ai-service"
    (root / "data").mkdir(parents=True)
    monkeypatch.setattr(rebuild, "AI_SERVICE_ROOT", root)

    for unsafe in (root, root.parent, root / "data" / "nested" / "runtime.kuzu"):
        with pytest.raises(ValueError):
            rebuild._validate_target(unsafe)


def test_rebuild_validates_quarantines_and_promotes(tmp_path, monkeypatch):
    root = tmp_path / "ai-service"
    data_dir = root / "data"
    (data_dir / "kg").mkdir(parents=True)
    target = data_dir / "runtime.kuzu"
    target.write_text("contaminated")
    Path(f"{target}_synced_files.json").write_text("old metadata")
    monkeypatch.setattr(rebuild, "AI_SERVICE_ROOT", root)
    monkeypatch.setattr(rebuild.time, "strftime", lambda *_args: "20260720-120000")

    import api.services.kg_service_v3 as kg_module

    class Closable:
        def close(self):
            pass

    class FakeKG:
        def __init__(self):
            replacement = Path(rebuild.os.environ["KUZU_DB_PATH"])
            replacement.write_text("clean")
            Path(f"{replacement}_synced_files.json").write_text("new metadata")
            self._conn = Closable()
            self._db = Closable()

    checked = []

    def fake_counts(path):
        checked.append(path)
        assert path.read_text() == "clean"
        return 7, 0

    monkeypatch.setattr(kg_module, "KnowledgeGraphServiceV3", FakeKG)
    monkeypatch.setattr(rebuild, "_counts", fake_counts)
    monkeypatch.setenv("KUZU_DB_PATH", "original")
    monkeypatch.setenv("KG_DATA_DIR", "original")

    quarantine = rebuild.rebuild(target)

    assert quarantine == data_dir / "runtime.kuzu.quarantine.20260720-120000"
    assert quarantine.read_text() == "contaminated"
    assert target.read_text() == "clean"
    assert Path(f"{quarantine}_synced_files.json").read_text() == "old metadata"
    assert Path(f"{target}_synced_files.json").read_text() == "new metadata"
    assert checked == [
        data_dir / f"runtime.kuzu.rebuild.{rebuild.os.getpid()}",
        target,
    ]


def test_rebuild_promotion_failure_rolls_source_and_metadata_back(tmp_path, monkeypatch):
    root = tmp_path / "ai-service"
    data_dir = root / "data"
    (data_dir / "kg").mkdir(parents=True)
    target = data_dir / "runtime.kuzu"
    target.write_text("contaminated")
    source_metadata = Path(f"{target}_synced_files.json")
    source_metadata.write_text("old metadata")
    monkeypatch.setattr(rebuild, "AI_SERVICE_ROOT", root)
    monkeypatch.setattr(rebuild.time, "strftime", lambda *_args: "20260720-120000")

    import api.services.kg_service_v3 as kg_module

    class Closable:
        def close(self):
            pass

    class FakeKG:
        def __init__(self):
            replacement = Path(rebuild.os.environ["KUZU_DB_PATH"])
            replacement.write_text("clean")
            Path(f"{replacement}_synced_files.json").write_text("new metadata")
            self._conn = Closable()
            self._db = Closable()

    monkeypatch.setattr(kg_module, "KnowledgeGraphServiceV3", FakeKG)
    monkeypatch.setattr(rebuild, "_counts", lambda _path: (7, 0))
    original_replace = Path.replace

    def fail_clean_promotion(path, destination):
        if path.name.startswith("runtime.kuzu.rebuild.") and Path(destination) == target:
            raise OSError("simulated promotion failure")
        return original_replace(path, destination)

    monkeypatch.setattr(Path, "replace", fail_clean_promotion)

    with pytest.raises(OSError, match="promotion failure"):
        rebuild.rebuild(target)

    quarantine = data_dir / "runtime.kuzu.quarantine.20260720-120000"
    assert target.read_text() == "contaminated"
    assert source_metadata.read_text() == "old metadata"
    assert not quarantine.exists()
    assert not Path(f"{quarantine}_synced_files.json").exists()
