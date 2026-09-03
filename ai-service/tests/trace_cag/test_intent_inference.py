from api.services.trace_cag.cache_utils import _infer_intent_pre_diagnosis as intent


def test_substring_lookalikes_do_not_hijack_the_intent():
    """`in` matching read "train" out of "restraint" and "who"/"where" out of
    "whole"/"somewhere". The intent feeds the graph bucket, so a misread filed
    the turn under the wrong cache bucket."""
    assert intent("Tell me about his restraint") == "correct"
    assert intent("Show me the trainer") == "correct"
    assert intent("a whole new world") == "correct"
    assert intent("Nowhere to go") == "correct"
    assert intent("Somewhere in Hanoi") == "correct"


def test_real_intents_still_resolve():
    assert intent("Why is this wrong") == "explain"
    assert intent("What does this mean") == "explain"
    assert intent("Give me practice questions") == "practice"
    assert intent("Let me train") == "practice"
    assert intent("Who wrote it") == "ask"
    assert intent("How many are there") == "ask"


def test_a_bare_question_mark_still_counts_as_asking():
    assert intent("Is this correct?") == "ask"


def test_priority_order_is_unchanged():
    """explain outranks practice outranks ask — the pre-existing contract."""
    assert intent("Why do I practice this?") == "explain"
    assert intent("Which exercise should I practice?") == "practice"
