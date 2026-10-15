from api.services.kg_data_loader import drop_noisy_edges

PAYLOAD = {
    "concepts": [],
    "edges": [
        {"from": "cefrlevel:a1", "to": "concept:vocab.word.paper", "relation": "related_to"},
        {"from": "cefrlevel:b1", "to": "concept:vocab.word.ship", "relation": "has_context"},
        {"from": "concept:vocab.word.even", "to": "concept:vocab.word.odd", "relation": "antonym"},
        {"from": "concept:vocab.word.a", "to": "concept:vocab.word.b", "relation": "related_to"},
        {"from": "concept:vocab.word.water", "to": "concept:vocab.word.ocean", "relation": "at_location"},
    ],
}


def test_lexical_dump_keeps_only_typed_non_cefr_edges():
    kept = drop_noisy_edges("/data/kg/12_lexical_relations.json", PAYLOAD)["edges"]
    assert [e["relation"] for e in kept] == ["antonym", "at_location"]


def test_other_sources_are_untouched():
    kept = drop_noisy_edges("/data/kg/06_tracecag_topic_expansion.json", PAYLOAD)
    assert kept is PAYLOAD
