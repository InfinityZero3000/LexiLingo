import json

from scripts.export_kuzu_mastery import export_rows


def test_export_is_versioned_bounded_and_has_checksum_manifest(tmp_path):
    output = tmp_path / "mastery.jsonl"
    manifest = tmp_path / "mastery.manifest.json"
    rows = [
        {"user_id": "user-2", "concept_id": "concept:b", "score": 0.7},
        {"user_id": "user-1", "concept_id": "concept:a", "score": 0.4},
    ]

    result = export_rows(iter(rows), output=output, manifest=manifest, page_size=1)

    exported = [json.loads(line) for line in output.read_text().splitlines()]
    metadata = json.loads(manifest.read_text())
    assert result["exported"] == 2
    assert all(item["schema_version"] == 1 for item in exported)
    assert metadata["sha256"] == result["sha256"]
    assert metadata["record_count"] == 2
    assert len(metadata["sha256"]) == 64
