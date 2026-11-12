from unittest.mock import MagicMock, patch

from api.services.lexi_chat_service import concept_labels


def _kg(concepts):
    kg = MagicMock(spec=["get_concepts"])
    kg.get_concepts.return_value = concepts
    return kg


def test_maps_known_ids_to_titles_and_skips_the_rest():
    kg = _kg({"concept:vocab.word.hello": {"title": " hello "}, "concept:x": {"title": ""}})
    with patch("api.services.kg_service_v3.get_kg_service", autospec=True, return_value=kg):
        assert concept_labels(["concept:vocab.word.hello", "concept:x", "concept:missing"]) == {
            "concept:vocab.word.hello": "hello"
        }


def test_kg_failure_yields_no_labels():
    with patch("api.services.kg_service_v3.get_kg_service", autospec=True, side_effect=RuntimeError):
        assert concept_labels(["concept:a"]) == {}
