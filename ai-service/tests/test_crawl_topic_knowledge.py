import json

from scripts.crawl_topic_knowledge import (
    GroqKeyPool,
    extract_json_object,
    merge_knowledge,
    render_knowledge_prefix,
    topic_concept_id,
    validate_extraction,
)


def test_groq_key_pool_rotates_and_persists_counts(tmp_path):
    state_path = tmp_path / "provider_quota_state.json"
    state_path.write_text(
        json.dumps(
            {
                "providers": {
                    "groq": {
                        "utc_day": "1900-01-01",
                        "index": 0,
                        "day_counts": {
                            "key-a": 42,
                            "key-b": 9,
                        },
                        "cooldown_until": {},
                    }
                }
            }
        ),
        encoding="utf-8",
    )

    pool = GroqKeyPool.from_state_file(state_path)

    first = pool.pick()
    second = pool.pick()
    assert {first, second} == {"key-a", "key-b"}

    pool.on_success(first)
    persisted = json.loads(state_path.read_text(encoding="utf-8"))
    counts = persisted["providers"]["groq"]["day_counts"]

    assert counts[first] == 1
    assert counts[second] == 0


def test_extract_json_object_strips_code_fences_and_text():
    parsed = extract_json_object(
        '```json\n{"concepts": [], "edges": [], "source_notes": []}\n```'
    )

    assert parsed == {"concepts": [], "edges": [], "source_notes": []}


def test_validate_extraction_adds_topic_and_filters_dangling_edges():
    story = {
        "story_id": "story_airport_checkin",
        "title": {"en": "Airport Check-In Adventure"},
        "difficulty_level": "A2",
        "category": "travel",
        "vocabulary_list": [{"term": "boarding pass", "definition": "A flight document"}],
        "grammar_points": [],
    }
    payload = {
        "concepts": [
            {
                "id": "entity:boarding_pass",
                "title": "Boarding Pass",
                "level": "A2",
                "keywords": "boarding pass flight gate",
            }
        ],
        "edges": [
            {"from": topic_concept_id("story_airport_checkin"), "to": "entity:boarding_pass", "relation": "contains"},
            {"from": "entity:boarding_pass", "to": "entity:missing", "relation": "related_to"},
        ],
    }

    validated = validate_extraction(payload, story, known_ids=set())
    concept_ids = {item["id"] for item in validated["concepts"]}
    edge_pairs = {(item["from"], item["to"]) for item in validated["edges"]}

    assert topic_concept_id("story_airport_checkin") in concept_ids
    assert "entity:boarding_pass" in concept_ids
    assert (topic_concept_id("story_airport_checkin"), "entity:boarding_pass") in edge_pairs
    assert ("entity:boarding_pass", "entity:missing") not in edge_pairs


def test_merge_knowledge_deduplicates_and_merges_keywords():
    existing = {
        "version": "1.1.0",
        "description": "Topic graph",
        "concepts": [
            {"id": "topic:airport_checkin", "title": "Airport", "level": "A2", "keywords": "airport gate"}
        ],
        "edges": [],
    }
    addition = {
        "concepts": [
            {
                "id": "topic:airport_checkin",
                "title": "Airport Check-In",
                "level": "A2",
                "keywords": "airport luggage passport",
            },
            {"id": "entity:passport", "title": "Passport", "level": "A2", "keywords": "passport id"},
        ],
        "edges": [
            {"from": "topic:airport_checkin", "to": "entity:passport", "relation": "contains"},
            {"from": "topic:airport_checkin", "to": "entity:passport", "relation": "contains"},
        ],
    }

    merged = merge_knowledge(existing, [addition])

    assert len(merged["concepts"]) == 2
    assert len(merged["edges"]) == 1
    airport = next(item for item in merged["concepts"] if item["id"] == "topic:airport_checkin")
    assert "gate" in airport["keywords"]
    assert "passport" in airport["keywords"]


def test_render_knowledge_prefix_uses_existing_format():
    graph = {
        "concepts": [
            {"id": "topic:airport_checkin", "title": "Airport Check-In", "level": "A2", "keywords": "airport"},
            {"id": "entity:boarding_pass", "title": "Boarding Pass", "level": "A2", "keywords": "boarding pass"},
        ],
        "edges": [
            {"from": "topic:airport_checkin", "to": "entity:boarding_pass", "relation": "contains"}
        ],
    }

    rendered = render_knowledge_prefix(graph)

    assert rendered.startswith("[LEXILINGO KNOWLEDGE BASE]\n")
    assert "- (Airport Check-In (Topic)) -[contains]-> (Boarding Pass (Vocabulary))" in rendered
    assert "[Source: topic_crawl]" in rendered
