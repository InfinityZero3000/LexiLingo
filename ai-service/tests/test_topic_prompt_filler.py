"""Template filler written by the old corpus generator must not reach the master prompt."""

import json
from pathlib import Path

from api.models.story_schemas import Story
from api.services.story_filler import (
    is_placeholder_definition,
    is_template_grammar_explanation,
    is_template_grammar_usage,
    is_template_vocab_example,
)
from api.services.subgraph_hot_cache import _extract_text_for_seeds
from api.services.topic_prompt_builder import TopicPromptBuilder

PLACEHOLDER = "A useful expression or concept for handling 'toothache' in the dental appointment checkup scenario"
TEMPLATE_GRAMMAR = "Use first conditional to keep the dental appointment checkup conversation clear and accurate."


def _story(vocab, grammar) -> Story:
    return Story(
        story_id="s",
        title={"en": "Dental", "vi": "Nha"},
        difficulty_level="B1",
        category="health",
        conversation_flow={"opening_prompt": "Hello"},
        vocabulary_list=vocab,
        grammar_points=grammar,
    )


def test_placeholder_definition_and_template_grammar_are_not_in_the_prompt():
    story = _story(
        [
            {"term": "toothache", "definition": PLACEHOLDER, "part_of_speech": "noun"},
            {"term": "cavity", "definition": "a hole in a tooth", "part_of_speech": "noun"},
        ],
        [
            {"grammar_structure": "First conditional", "explanation": TEMPLATE_GRAMMAR},
            {"grammar_structure": "Modals for advice", "explanation": "Use should to give advice."},
        ],
    )

    prompt = TopicPromptBuilder.build_master_prompt(story)

    assert "A useful expression" not in prompt
    assert "clear and accurate" not in prompt
    assert "- **toothache** (noun)\n" in prompt
    assert "- **cavity** (noun): a hole in a tooth" in prompt
    assert "- First conditional\n" in prompt
    assert "- Modals for advice: Use should to give advice." in prompt


def test_empty_definition_and_explanation_leave_no_dangling_colon():
    story = _story(
        [{"term": "toothache", "definition": "", "part_of_speech": "noun"}],
        [{"grammar_structure": "First conditional", "explanation": ""}],
    )

    prompt = TopicPromptBuilder.build_master_prompt(story)

    assert "- **toothache** (noun)\n" in prompt
    assert "- First conditional\n" in prompt
    assert "(noun): \n" not in prompt


def test_prompt_no_longer_asks_for_tip_brackets():
    prompt = TopicPromptBuilder.build_master_prompt(_story([], []))

    assert "[\U0001F4A1 Tip: brief grammar explanation]" not in prompt
    assert "Do NOT write grammar notes" in prompt


def test_kg_seed_text_skips_filler_but_keeps_real_definitions():
    text = _extract_text_for_seeds(
        [
            {"term": "toothache", "definition": PLACEHOLDER},
            {"term": "cavity", "definition": "a hole in a tooth"},
        ],
        [{"topic": "conditionals", "explanation": TEMPLATE_GRAMMAR}],
    )

    assert "useful expression" not in text and "clear and accurate" not in text
    assert "toothache" in text and "a hole in a tooth" in text


def test_filler_detectors():
    assert is_placeholder_definition(PLACEHOLDER)
    assert is_placeholder_definition("")
    assert not is_placeholder_definition("a hole in a tooth")
    assert is_template_grammar_explanation(TEMPLATE_GRAMMAR)
    assert not is_template_grammar_explanation("Use should to give advice.")
    assert is_template_grammar_usage(
        "This structure helps the learner ask, explain, or respond during hotel check-in."
    )
    assert is_template_vocab_example("Could you help me with the room key during this hotel check-in?")
    assert not is_template_vocab_example("Could you hold my room key, please?")


def test_every_current_sample_story_prompt_builds_without_filler():
    path = Path(__file__).resolve().parents[1] / "data" / "sample_stories.json"
    stories = json.loads(path.read_text(encoding="utf-8"))["stories"]
    for payload in stories:
        prompt = TopicPromptBuilder.build_master_prompt(Story(**payload))
        assert "A useful expression or concept for handling" not in prompt, payload["story_id"]
        assert "conversation clear and accurate" not in prompt, payload["story_id"]
