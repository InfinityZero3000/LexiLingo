import json
from pathlib import Path

from api.models.content_agent import (
    CEFRLevel,
    ContentAgentArtifact,
    NormalizedSourceRecord,
    PartOfSpeech,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
CONTRACT_ROOT = REPO_ROOT / "contracts" / "content-agent"


def _contract(filename: str) -> dict:
    return json.loads((CONTRACT_ROOT / filename).read_text(encoding="utf-8"))


def test_shared_source_contract_matches_ai_enums_and_rejects_unknown_fields():
    contract = _contract("source-record-v2.schema.json")

    assert set(contract["$defs"]["cefrLevel"]["enum"]) == {
        level.value for level in CEFRLevel
    }
    assert set(contract["$defs"]["partOfSpeech"]["enum"]) == {
        part.value for part in PartOfSpeech
    }
    assert contract["additionalProperties"] is False
    assert {
        "schema_version",
        "record_id",
        "source_name",
        "source_version",
        "source_record_id",
        "source_url",
        "license_id",
        "license_url",
        "attribution_text",
        "content_usage",
        "language",
        "retrieved_at",
        "raw_checksum",
        "record_checksum",
        "lineage",
    }.issubset(contract["required"])
    assert NormalizedSourceRecord.model_config["extra"] == "forbid"


def test_shared_course_artifact_contract_matches_ai_version():
    contract = _contract("course-artifact-v2.schema.json")

    assert contract["properties"]["schema_version"]["const"] == 2
    assert contract["properties"]["prompt_version"]["const"] == "cefr-course-v2"
    assert ContentAgentArtifact.model_fields["schema_version"].default == 2
    assert (
        ContentAgentArtifact.model_fields["prompt_version"].default
        == "cefr-course-v2"
    )
    assert ContentAgentArtifact.model_config["extra"] == "forbid"
    manifest = contract["properties"]["source_manifest"]
    assert manifest["minItems"] == 1
    assert manifest["items"]["$ref"] == "#/$defs/sourceManifest"
    assert contract["$defs"]["sourceManifest"]["additionalProperties"] is False
    assert {
        "raw_checksum",
        "normalized_sha256",
        "normalized_bytes",
        "record_checksum_root",
    }.issubset(contract["$defs"]["sourceManifest"]["required"])


def test_shared_exercise_mapping_uses_only_supported_base_types():
    contract = _contract("exercise-types-v1.json")
    supported = {
        "multiple_choice",
        "true_false",
        "fill_blank",
        "translate",
        "matching",
        "reorder",
    }

    assert set(contract["base_types"]) == supported
    assert set(contract["ui_type_to_type"].values()) <= supported
    assert len(contract["ui_type_to_type"]) == len(set(contract["ui_type_to_type"]))
