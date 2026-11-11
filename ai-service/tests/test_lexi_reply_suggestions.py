import asyncio
from unittest.mock import MagicMock, patch

from api.services import lexi_reply_suggestions as svc


def test_question_detection_covers_ascii_and_fullwidth():
    assert svc.ends_with_question("How do you get to work? 🦜")
    assert svc.ends_with_question("あなたは何をしていますか？")
    assert not svc.ends_with_question("Great job today!")


def test_parse_options_strips_fences_dedupes_and_caps():
    raw = '```json\n["Yes, I do.", "Yes, I do.", "No.", 3, "  Maybe.  ", "Four"]\n```'
    assert svc.parse_options(raw) == ["Yes, I do.", "No.", "Maybe."]


def test_parse_options_rejects_garbage_and_long_items():
    assert svc.parse_options("no json here") == []
    assert svc.parse_options("[not valid") == []
    assert svc.parse_options('["' + "x" * 500 + '"]') == []


def test_no_llm_call_for_a_non_question():
    with patch("api.core.groq_key_pool.get_available_groq_key", autospec=True) as key:
        assert asyncio.run(svc.suggest_replies("Nice work!")) == []
    key.assert_not_called()


def test_suggest_replies_returns_parsed_options():
    resp = MagicMock(status_code=200)
    resp.json.return_value = {
        "choices": [{"message": {"content": '["I walk.", "By bus."]'}}],
        "usage": {"total_tokens": 90},
    }
    with (
        patch("api.core.groq_key_pool.get_available_groq_key", autospec=True, return_value="k"),
        patch("api.core.groq_key_pool.record_groq_key_usage", autospec=True) as usage,
        patch(
            "api.services.trace_cag.llm_client._throttled_post_json",
            autospec=True,
            return_value=resp,
        ),
    ):
        assert asyncio.run(svc.suggest_replies("How do you get to work?")) == ["I walk.", "By bus."]
    usage.assert_called_once()


def test_suggest_replies_degrades_to_empty_when_llm_fails():
    with (
        patch("api.core.groq_key_pool.get_available_groq_key", autospec=True, return_value="k"),
        patch(
            "api.services.trace_cag.llm_client._throttled_post_json",
            autospec=True,
            side_effect=RuntimeError("boom"),
        ),
    ):
        assert asyncio.run(svc.suggest_replies("Where do you live?")) == []
