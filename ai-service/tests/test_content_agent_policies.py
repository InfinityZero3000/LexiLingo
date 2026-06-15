from datetime import date

import pytest

from api.services.content_agent.policies import (
    SOURCE_POLICIES,
    SourcePolicyError,
    apply_source_policy,
    get_source_policy,
)


def test_approved_lexical_policy_preserves_only_supported_content_fields():
    record = apply_source_policy(
        "oewn",
        {
            "record_id": "oewn:2025:1",
            "source_url": "https://github.com/globalwordnet/english-wordnet",
            "title": "Open English WordNet",
            "word": "journey",
            "part_of_speech": "noun",
            "definition": "An act of travelling from one place to another.",
            "declared_cefr": "A2",
            "declared_topic": "travel",
            "metadata": {
                "resource_type": "lexical",
                "unapproved_field": "must not survive",
            },
        },
    )

    serialized = record.model_dump_json()
    assert record.content_usage == "full_text"
    assert record.word == "journey"
    assert record.definition.startswith("An act of travelling")
    assert "must not survive" not in serialized


def test_registry_contains_only_approved_dataset_sources_and_compatibility_alias():
    assert set(SOURCE_POLICIES) == {
        "existing_cefr",
        "admin_upload",
        "oewn",
        "cmudict",
        "cefr_j",
        "wikidata",
        "tatoeba",
        "librispeech",
        "common_voice",
    }


@pytest.mark.parametrize(
    "source_name",
    [
        "voa",
        "bbc",
        "british_council",
        "cambridge_english",
        "cambridge_dictionary",
        "oxford",
        "dol",
        "prep",
        "ielts_workshop",
        "wiktionary",
        "conceptnet",
    ],
)
def test_denied_sources_are_unsupported(source_name):
    with pytest.raises(SourcePolicyError, match="Unsupported content source"):
        get_source_policy(source_name)


def test_unknown_and_expired_policies_fail_closed():
    with pytest.raises(SourcePolicyError):
        get_source_policy("not_allowlisted")

    with pytest.raises(SourcePolicyError):
        get_source_policy("oewn", as_of=date(2030, 1, 1))
