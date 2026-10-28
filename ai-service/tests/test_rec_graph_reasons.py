from api.services.rec_graph.nodes import _reason_for, _reason_parts


def test_reason_has_code_args_and_vietnamese_fallback() -> None:
    item = {"features": {"topic": 0.8}, "topic": "travel"}
    assert _reason_parts(item, {}) == ("topic", {"topic": "travel"})
    assert _reason_for(item, {}) == "Bạn học nhiều về chủ đề travel"


def test_due_beats_everything_and_default_is_last() -> None:
    assert _reason_parts({"features": {"due": 1, "topic": 1}}, {})[0] == "due"
    assert _reason_parts({"features": {}}, {}) == ("default", {})
    level = {"features": {"cefr_fit": 1.0}}
    assert _reason_parts(level, {"level": "B1"}) == ("level", {"level": "B1"})
