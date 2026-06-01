from api.models.story_schemas import Story
from scripts.generate_tracecag_topic_corpus import (
    BLUEPRINTS,
    generate_tracecag_graph,
    merge_stories,
    story_from_blueprint,
    validate_outputs,
)


def _generated_stories():
    return [story_from_blueprint(blueprint) for blueprint in BLUEPRINTS]


def test_generated_story_ids_are_unique():
    stories = _generated_stories()
    story_ids = [story["story_id"] for story in stories]

    assert len(stories) == 60
    assert len(story_ids) == len(set(story_ids))


def test_generated_stories_parse_with_story_schema():
    for story in _generated_stories():
        parsed = Story(**story)
        assert parsed.story_id == story["story_id"]
        assert parsed.is_published is True
        assert len(parsed.vocabulary_list) >= 10
        assert len(parsed.grammar_points) >= 3


def test_tracecag_quadruple_and_edge_counts_exceed_target():
    stories = _generated_stories()
    graph, quadruples, edges = generate_tracecag_graph(stories)

    assert len(quadruples) > 10_000
    assert len(edges) > 10_000
    assert len(graph["concepts"]) > 1_000
    assert len(graph["edges"]) > 10_000


def test_generated_kg_has_no_dangling_edges_or_duplicates():
    stories = _generated_stories()
    graph, quadruples, edges = generate_tracecag_graph(stories)
    report = validate_outputs(stories, graph, quadruples, edges, min_lines=10_000)

    assert report["ok"] is True
    assert report["duplicate_story_ids"] == 0
    assert report["duplicate_concepts"] == 0
    assert report["duplicate_edges"] == 0
    assert report["dangling_edges"] == 0


def test_merge_stories_appends_generated_topics_without_replacing_existing():
    existing = [
        {
            "story_id": "story_existing",
            "title": {"en": "Existing", "vi": "Existing"},
            "difficulty_level": "A1",
            "category": "daily_life",
            "context_description": {"setting": "", "scenario": "", "objectives": []},
            "role_persona": {
                "name": "Lexi",
                "role": "Tutor",
                "personality": "Helpful",
                "speaking_style": "Clear",
                "background": "Tutor",
            },
            "conversation_flow": {"opening_prompt": "Hello"},
            "is_published": True,
        }
    ]

    merged = merge_stories(existing, _generated_stories())

    assert merged[0]["story_id"] == "story_existing"
    assert len(merged) == 61
