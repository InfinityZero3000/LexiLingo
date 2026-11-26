import json

import pytest

from api.services.internal_payloads import strip_jit_graph_blocks
from api.services.lexi_pipeline_helpers import sanitize_lexi_response
from api.services.topic_chat_service import sanitize_topic_response


@pytest.mark.parametrize("clean", [strip_jit_graph_blocks, sanitize_lexi_response, sanitize_topic_response])
def test_nested_multiple_inline_blocks_preserve_prose(clean):
    payload = json.dumps({"nodes": [{"text": 'escaped \\" } {'}], "edges": [[1, 2]]})
    text = f"Hello. [JIT_SOFT_GRAPH]{payload} World. [jit_soft_graph]\n{payload} Goodbye."
    assert " ".join(clean(text).split()) == "Hello. World. Goodbye."


@pytest.mark.parametrize("tail", ['{"nodes":[{"id":"secret"}', '{invalid} fragments', '', '[1,2]'])
@pytest.mark.parametrize("clean", [strip_jit_graph_blocks, sanitize_lexi_response, sanitize_topic_response])
def test_truncated_payload_discards_unsafe_tail(clean, tail):
    assert clean("Safe prose. [JIT_SOFT_GRAPH]" + tail) == "Safe prose."


def test_ordinary_json_is_not_removed_without_internal_marker():
    assert strip_jit_graph_blocks('Example: {"a":1}') == 'Example: {"a":1}'


@pytest.mark.parametrize("clean", [strip_jit_graph_blocks, sanitize_lexi_response, sanitize_topic_response])
def test_marker_followed_by_prose_keeps_the_prose(clean):
    assert " ".join(clean("Hello. [JIT_SOFT_GRAPH] Paris is the capital.").split()) == "Hello. Paris is the capital."


@pytest.mark.parametrize("clean", [strip_jit_graph_blocks, sanitize_lexi_response, sanitize_topic_response])
def test_marker_with_truncated_object_still_drops_tail(clean):
    assert clean('Safe. [JIT_SOFT_GRAPH] {"v":[') == "Safe."


def test_complete_blocks_keep_prose_between_and_after():
    text = 'A. [JIT_SOFT_GRAPH]{"a":1} B. [JIT_SOFT_GRAPH] C. [JIT_SOFT_GRAPH]{"b":[2]} D.'
    assert " ".join(strip_jit_graph_blocks(text).split()) == "A. B. C. D."
