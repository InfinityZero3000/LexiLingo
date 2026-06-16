import uuid

import pytest
from pydantic import ValidationError

from app.schemas.content_agent import ContentAgentJobCreate
from app.services.vocabulary_catalog import normalize_word


def test_rollout_stage_one_accepts_internal_and_uploaded_sources() -> None:
    request = ContentAgentJobCreate(
        levels=["A1", "A2"],
        sources=["existing_cefr"],
        exercise_mix={"speaking": 2, "listening": 2},
    )

    assert request.levels == ["A1", "A2"]
    assert request.words_per_lesson == 10


def test_accepts_approved_dataset_source_ids() -> None:
    request = ContentAgentJobCreate(
        levels=["A1"],
        sources=["oewn", "cmudict", "cefr_j", "wikidata"],
    )

    assert request.sources == ["oewn", "cmudict", "cefr_j", "wikidata"]


@pytest.mark.parametrize(
    "source_name",
    ["bbc", "british_council", "cambridge_dictionary", "oxford", "voa"],
)
def test_rejects_removed_web_source_ids(source_name: str) -> None:
    with pytest.raises(ValidationError, match="unsupported sources"):
        ContentAgentJobCreate(levels=["A1"], sources=[source_name])


def test_exercise_mix_must_fit_total() -> None:
    with pytest.raises(ValidationError, match="must fit"):
        ContentAgentJobCreate(
            levels=["A1"],
            sources=["existing_cefr"],
            exercises_per_lesson=4,
            exercise_mix={"speaking": 3, "listening": 2},
        )


def test_upload_id_and_admin_upload_source_must_be_selected_together() -> None:
    upload_id = uuid.uuid4()
    with pytest.raises(ValidationError, match="admin_upload must be selected"):
        ContentAgentJobCreate(
            levels=["A1"],
            sources=["existing_cefr"],
            upload_id=upload_id,
        )
    with pytest.raises(ValidationError, match="upload_id is required"):
        ContentAgentJobCreate(levels=["A1"], sources=["admin_upload"])


def test_vocabulary_normalization_handles_em_dash_and_casefold() -> None:
    # em dash -> hyphen, uppercase -> lowercase, strip whitespace
    raw = "  Café—Menu  "   # "  Café—Menu  "
    result = normalize_word(raw)
    assert result == "café-menu"


def test_vocabulary_normalization_converts_curly_apostrophe() -> None:
    # U+2019 right single quotation mark -> U+0027 straight apostrophe
    raw = "it’s"
    result = normalize_word(raw)
    assert result == "it's"
