"""The grader turns an LLM reply into a band, and that arithmetic must hold.

Every test here fakes the Groq call: what is under test is the prompt we send,
the clamping of whatever the model returns, and the half-band rounding.
"""

import json

import pytest

from api.services import ielts_grader


class _FakeResponse:
    def __init__(self, payload, status_code=200, text=""):
        self._payload = payload
        self.status_code = status_code
        self.text = text

    def json(self):
        return self._payload


def _reply(criteria: dict, **extra) -> _FakeResponse:
    body = {"criteria": criteria, **extra}
    return _FakeResponse(
        {"choices": [{"message": {"content": json.dumps(body)}}]}
    )


@pytest.fixture
def patched(monkeypatch):
    """Capture the payload the grader would post, and control the reply."""
    sent = {}

    async def fake_key(**_kwargs):
        return "test-key"

    def install(response):
        async def fake_post(*, provider, url, payload, headers, timeout):
            sent["provider"] = provider
            sent["payload"] = payload
            return response

        monkeypatch.setattr(ielts_grader, "_throttled_post_json", fake_post)

    monkeypatch.setattr(ielts_grader, "get_available_groq_key", fake_key)
    return sent, install


def test_quarter_band_mean_rounds_up(patched):
    sent, install = patched
    install(
        _reply(
            {
                "task_achievement": 6,
                "coherence_cohesion": 6,
                "lexical_resource": 6.5,
                "grammatical_range": 6.5,
            }
        )
    )
    result = _run(
        skill="writing", part_key="writing_task_2", answer_text="word " * 260
    )
    # Mean is 6.25. Python's round() would give 6.0; IELTS gives 6.5.
    assert result["band"] == 6.5


def test_band_is_clamped_and_snapped_to_half(patched):
    _sent, install = patched
    install(
        _reply(
            {
                "task_achievement": 12,        # above the scale
                "coherence_cohesion": -3,      # below it
                "lexical_resource": "not a number",
                "grammatical_range": 6.3,      # not a half band
            }
        )
    )
    result = _run(skill="writing", part_key="writing_task_1", answer_text="a b c")
    assert result["criteria"] == {
        "task_achievement": 9.0,
        "coherence_cohesion": 0.0,
        "lexical_resource": 0.0,
        "grammatical_range": 6.5,
    }
    assert result["band"] == 4.0


def test_missing_criteria_score_zero_not_dropped(patched):
    _sent, install = patched
    install(_reply({"fluency_coherence": 7}))
    result = _run(
        skill="speaking", part_key="speaking_part_2", answer_text="I think so."
    )
    assert set(result["criteria"]) == set(ielts_grader.SPEAKING_CRITERIA)
    assert result["criteria"]["pronunciation"] == 0.0


def test_writing_prompt_states_the_length_requirement(patched):
    sent, install = patched
    install(_reply({key: 7 for key in ielts_grader.WRITING_CRITERIA}))
    _run(skill="writing", part_key="writing_task_2", answer_text="word " * 199)
    prompt = sent["payload"]["messages"][1]["content"]
    assert "minimum is 250 words" in prompt
    assert "has 199" in prompt
    assert sent["payload"]["response_format"] == {"type": "json_object"}
    # The qwen reasoning override is injected by _throttled_post_json; posting
    # with a raw client here would break json_object mode.
    assert sent["provider"] == "groq"


def test_speaking_uses_the_speaking_descriptors(patched):
    sent, install = patched
    install(_reply({key: 7 for key in ielts_grader.SPEAKING_CRITERIA}))
    result = _run(
        skill="speaking", part_key="speaking_part_1", answer_text="Yes, I do."
    )
    prompt = sent["payload"]["messages"][1]["content"]
    assert "Pronunciation" in prompt
    assert "Task Achievement" not in prompt
    assert result["grader_version"] == ielts_grader.GRADER_VERSION


def test_feedback_lists_are_bounded(patched):
    _sent, install = patched
    install(
        _reply(
            {key: 7 for key in ielts_grader.WRITING_CRITERIA},
            reasoning="x" * 5000,
            strengths=[f"s{i}" for i in range(20)],
            improvements=[f"i{i}" for i in range(20)],
            corrections=[{"original": "a", "corrected": "b", "note": "c"}] * 30
            + ["not a dict"],
        )
    )
    feedback = _run(
        skill="writing", part_key="writing_task_1", answer_text="hello"
    )["feedback"]
    assert len(feedback["reasoning"]) == 2000
    assert len(feedback["strengths"]) == 5
    assert len(feedback["improvements"]) == 5
    assert len(feedback["corrections"]) == 10


def test_non_200_raises_rather_than_inventing_a_band(patched):
    _sent, install = patched
    install(_FakeResponse({}, status_code=429, text="rate limited"))
    with pytest.raises(RuntimeError, match="429"):
        _run(skill="writing", part_key="writing_task_1", answer_text="hello")


@pytest.mark.parametrize(
    "skill,answer",
    [("listening", "hello"), ("writing", "   ")],
)
def test_ungradable_input_is_rejected_before_the_call(skill, answer):
    with pytest.raises(ValueError):
        _run(skill=skill, part_key="writing_task_1", answer_text=answer)


def _run(**kwargs):
    import asyncio

    return asyncio.run(
        ielts_grader.grade_submission(task_prompt="Describe the chart.", **kwargs)
    )
