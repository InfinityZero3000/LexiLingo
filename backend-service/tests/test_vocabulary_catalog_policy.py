from dataclasses import replace
from datetime import datetime, timezone
from uuid import uuid4

import pytest

from app.services.vocabulary_catalog_policy import (
    STARTER_TOPIC_QUOTAS,
    VocabularyCandidate,
    is_placeholder_definition,
    normalize_all_tags,
    normalize_topic_tags,
    select_balanced_starter_vocabulary,
)


@pytest.mark.parametrize(
    "definition",
    [
        "",
        "   ",
        "#N/A",
        "#N/A yet",
        " n/a YET ",
        "N.A.",
        "not available",
        "---",
    ],
)
def test_placeholder_definitions_are_rejected(definition):
    assert is_placeholder_definition(definition) is True


@pytest.mark.parametrize(
    "definition",
    [
        "A useful English definition.",
        "Hội chứng suy giảm miễn dịch mắc phải",
        "Available for daily use",
    ],
)
def test_real_definitions_are_kept(definition):
    assert is_placeholder_definition(definition) is False


def test_normalize_topic_tags_supports_legacy_and_structured_payloads():
    assert normalize_topic_tags("daily_life") == ("daily",)
    assert normalize_topic_tags(["travel", "daily_life"]) == ("travel", "daily")
    assert normalize_topic_tags({"topic": "technology"}) == ("technology",)
    assert normalize_topic_tags({"tags": ["science", "general"]}) == (
        "science",
        "general",
    )


def test_normalize_all_tags_preserves_source_and_canonicalizes_daily():
    assert normalize_all_tags(
        {
            "source": "anki_5000",
            "topic": "daily_life",
            "anki_tags": ["Travel", "travel"],
        }
    ) == ["anki_5000", "daily", "travel"]


def test_balanced_selection_has_exact_quotas_and_unique_items():
    candidates = []
    for topic, quota in STARTER_TOPIC_QUOTAS.items():
        for index in range(quota + 3):
            candidates.append(
                VocabularyCandidate(
                    id=uuid4(),
                    word=f"{topic}-{index:02d}",
                    definition=f"Definition for {topic} {index}",
                    usage_frequency=1000 - index,
                    tags=[topic],
                )
            )

    candidates.append(
        VocabularyCandidate(
            id=uuid4(),
            word="invalid-placeholder",
            definition="#N/A yet",
            usage_frequency=9999,
            tags=["general"],
        )
    )

    selected = select_balanced_starter_vocabulary(candidates)

    assert len(selected) == 200
    assert len({assignment.candidate.id for assignment in selected}) == 200
    assert {
        topic: sum(assignment.topic == topic for assignment in selected)
        for topic in STARTER_TOPIC_QUOTAS
    } == STARTER_TOPIC_QUOTAS
    assert all(
        assignment.candidate.word != "invalid-placeholder" for assignment in selected
    )


def test_balanced_selection_prefers_frequency_then_word():
    base = [
        VocabularyCandidate(
            id=uuid4(),
            word=f"{topic}-{index:02d}",
            definition="Valid definition",
            usage_frequency=1000 - index,
            tags=[topic],
        )
        for topic, quota in STARTER_TOPIC_QUOTAS.items()
        for index in range(quota)
    ]
    lowest_general = next(
        candidate
        for candidate in base
        if normalize_topic_tags(candidate.tags) == ("general",)
        and candidate.usage_frequency == 967
    )
    preferred = replace(
        lowest_general,
        id=uuid4(),
        word="a-preferred-general-word",
        usage_frequency=5000,
    )

    selected = select_balanced_starter_vocabulary([*base, preferred])
    general_words = {
        assignment.candidate.word
        for assignment in selected
        if assignment.topic == "general"
    }

    assert "a-preferred-general-word" in general_words
    assert lowest_general.word not in general_words


def test_balanced_selection_uses_import_order_when_frequency_is_missing():
    candidates = [
        VocabularyCandidate(
            id=uuid4(),
            word=f"{topic}-{index:02d}",
            definition="Valid definition",
            usage_frequency=0,
            tags=[topic],
            created_at=datetime(
                2026,
                1,
                min(index + 1, 28),
                tzinfo=timezone.utc,
            ),
        )
        for topic, quota in STARTER_TOPIC_QUOTAS.items()
        for index in range(quota)
    ]
    late_general = next(
        candidate for candidate in candidates if candidate.word == "general-33"
    )
    earlier_general = replace(
        late_general,
        id=uuid4(),
        word="z-earlier-import",
        created_at=datetime(2025, 1, 1, tzinfo=timezone.utc),
    )

    selected = select_balanced_starter_vocabulary([*candidates, earlier_general])
    general_words = {
        assignment.candidate.word
        for assignment in selected
        if assignment.topic == "general"
    }

    assert "z-earlier-import" in general_words
    assert "general-33" not in general_words


def test_balanced_selection_fails_when_a_topic_is_undersized():
    candidates = [
        VocabularyCandidate(
            id=uuid4(),
            word=f"{topic}-{index:02d}",
            definition="Valid definition",
            usage_frequency=1000 - index,
            tags=[topic],
        )
        for topic, quota in STARTER_TOPIC_QUOTAS.items()
        for index in range(quota - (1 if topic == "science" else 0))
    ]

    with pytest.raises(ValueError, match="science"):
        select_balanced_starter_vocabulary(candidates)
