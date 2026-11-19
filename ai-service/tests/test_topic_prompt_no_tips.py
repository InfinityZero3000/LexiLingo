"""The master prompt must not ask the persona to write grammar notes."""

from api.services import topic_prompt_builder as tpb
from api.services.educational_hints_parser import EducationalHintsParser


def test_few_shot_examples_have_no_tip_brackets_and_keep_vocab_hint():
    assert "[\U0001F4A1" not in tpb.FEW_SHOT_EXAMPLES
    assert "[\U0001F4D8" in tpb.FEW_SHOT_EXAMPLES


def test_few_shot_vocab_example_still_parses():
    _, hints = EducationalHintsParser.parse(tpb.FEW_SHOT_EXAMPLES.split("Response: ")[2])
    assert hints is not None and hints.vocabulary_hints[0].term == "boarding pass"


def test_instruction_text_forbids_tip_brackets():
    src = open(tpb.__file__, encoding="utf-8").read()
    assert "[\U0001F4A1 Tip: brief grammar explanation]" not in src
    assert '"grammar_corrections"' not in src
    assert "Do NOT write grammar notes" in src
