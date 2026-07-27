from api.services.trace_cag.benchmark.ranking import _interleave_explicit_second_hop


def _items():
    return [
        {"title": "Film A", "text": "Film A was directed by Person B", "item_id": "film", "source_version": "s1", "fusion_score": 0.9},
        {"title": "Noise", "text": "unrelated", "item_id": "noise", "source_version": "s2", "fusion_score": 0.8},
        {"title": "Person B", "text": "Person B was born in 1980", "item_id": "person", "source_version": "s3", "fusion_score": 0.3},
    ]


def test_second_hop_is_noop_when_disabled():
    items = _items()
    assert _interleave_explicit_second_hop(items, enabled=False) is items


def test_second_hop_preserves_rank_one_and_provenance():
    ranked = _interleave_explicit_second_hop(_items(), enabled=True)
    assert [item["title"] for item in ranked] == ["Film A", "Person B", "Noise"]
    assert ranked[1]["item_id"] == "person"
    assert ranked[1]["source_version"] == "s3"


def test_second_hop_deduplicates_titles():
    items = _items() + [{**_items()[2], "item_id": "duplicate"}]
    ranked = _interleave_explicit_second_hop(items, enabled=True)
    assert [item["title"] for item in ranked].count("Person B") == 1


def test_second_hop_preserves_untitled_candidates():
    items = _items() + [
        {"title": "", "text": "first", "item_id": "untitled-1"},
        {"title": "", "text": "second", "item_id": "untitled-2"},
    ]

    ranked = _interleave_explicit_second_hop(items, enabled=True)

    assert [item["item_id"] for item in ranked[-2:]] == ["untitled-1", "untitled-2"]
