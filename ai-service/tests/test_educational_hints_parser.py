"""Regression test: bracket hint parsing must not depend on the exact emoji glyph."""

from api.services.educational_hints_parser import EducationalHintsParser


def test_vocab_bracket_parsed_regardless_of_emoji():
    response = (
        "Here's our menu for tonight. "
        "[\U0001F4DC 'menu' means a list of food and drinks available at a restaurant. "
        "Example: 'Can I see the menu, please?'] "
        "We have many delicious options."
    )
    clean, hints = EducationalHintsParser.parse(response)

    assert "[" not in clean and "]" not in clean
    assert hints is not None
    assert len(hints.vocabulary_hints) == 1
    hint = hints.vocabulary_hints[0]
    assert hint.term == "menu"
    assert "list of food" in hint.definition
    assert hint.example == "Can I see the menu, please?"


def test_tip_bracket_not_miscategorized_as_vocab():
    response = "You went there. [\U0001F4A1 Tip: use 'went' not 'go' for past actions.]"
    clean, hints = EducationalHintsParser.parse(response)

    assert "[" not in clean
    assert hints is not None
    assert len(hints.grammar_corrections) == 1
    assert not hints.vocabulary_hints


def test_merge_diagnosis_errors_adds_when_no_bracket_hints():
    diagnosis_errors = [
        {"span": "I go", "type": "tense_error", "correction": "I went", "explanation": "past tense"},
    ]
    merged = EducationalHintsParser.merge_diagnosis_errors(None, diagnosis_errors)

    assert merged is not None
    assert len(merged.grammar_corrections) == 1
    assert merged.grammar_corrections[0].corrected == "I went"


def test_merge_diagnosis_errors_dedupes_against_bracket_hint():
    # The bracket tip's "use 'went' not 'go'" phrasing lets _parse_tip_text
    # already extract corrected="went" — the diagnosis_errors entry for the
    # same correction must not add a second, duplicate card.
    response = "You went there. [\U0001F4A1 Tip: use 'went' not 'go' for past actions.]"
    _, hints = EducationalHintsParser.parse(response)
    diagnosis_errors = [
        {"span": "go", "type": "tense_error", "correction": "went", "explanation": "past tense needed"},
    ]

    merged = EducationalHintsParser.merge_diagnosis_errors(hints, diagnosis_errors)

    assert merged is not None
    assert len(merged.grammar_corrections) == 1


def test_merge_diagnosis_errors_skips_duplicate_correction_text():
    hints = EducationalHintsParser._parse_brackets(
        "[\U0001F4A1 Tip: We say 'went' not 'go'.]"
    )
    diagnosis_errors = [
        {"span": "go", "type": "tense_error", "correction": "went", "explanation": "already covered"},
    ]

    merged = EducationalHintsParser.merge_diagnosis_errors(hints, diagnosis_errors)

    assert len(merged.grammar_corrections) == 1  # not doubled


if __name__ == "__main__":
    test_vocab_bracket_parsed_regardless_of_emoji()
    test_tip_bracket_not_miscategorized_as_vocab()
    print("ok")
