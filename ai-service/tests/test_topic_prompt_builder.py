import json
from pathlib import Path

from api.models.story_schemas import Story
from api.services.topic_prompt_builder import TopicPromptBuilder


def _load_sample_story() -> Story:
    sample_path = Path(__file__).resolve().parents[1] / "data" / "sample_stories.json"
    payload = json.loads(sample_path.read_text(encoding="utf-8"))
    return Story(**payload["stories"][0])


def test_build_master_prompt_supports_dict_vocab_and_grammar_items():
    story = _load_sample_story()

    prompt = TopicPromptBuilder.build_master_prompt(story)

    assert "Sarah" in prompt
    assert "boarding pass" in prompt
    assert "Present Simple for Schedules" in prompt


def test_build_master_prompt_handles_missing_optional_context_fields():
    story = _load_sample_story()
    story = story.model_copy(
        update={
            "role_persona": None,
            "context_description": None,
        }
    )

    prompt = TopicPromptBuilder.build_master_prompt(story)

    assert "LexiLingo Tutor" in prompt
    assert "A realistic English practice setting" in prompt