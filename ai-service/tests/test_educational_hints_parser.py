"""Hints parser: vocab brackets parse; corrections come only from grounded diagnosis."""

from api.services.educational_hints_parser import EducationalHintsParser


def _diag(span, correction, type_="subject_verb_agreement", explanation="x"):
    return {"span": span, "type": type_, "correction": correction, "explanation": explanation}


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


def test_tip_bracket_is_stripped_but_creates_no_correction():
    response = "Those are the rules. [\U0001F4A1 Tip: We say 'the rules' not 'rules' - the article.]"
    clean, hints = EducationalHintsParser.parse(response)

    assert "[" not in clean and "Tip" not in clean
    assert hints is None


def test_json_block_grammar_corrections_are_ignored():
    response = (
        '{"character_response": "Here you go.", "educational_hints": {"grammar_corrections": '
        '[{"error": "I goes", "correction": "I go", "explanation": "x"}], '
        '"vocabulary_hints": [{"term": "pass", "definition": "ticket"}]}}'
    )
    _, hints = EducationalHintsParser.parse(response)

    assert hints is not None
    assert hints.grammar_corrections == []
    assert [v.term for v in hints.vocabulary_hints] == ["pass"]


def test_grounded_diagnosis_becomes_a_correction_with_closed_label():
    hints, accepted = EducationalHintsParser.corrections_from_diagnosis(
        None, [_diag("I has", "I have")], "I has a toothache since yesterday"
    )

    assert hints is not None and len(hints.grammar_corrections) == 1
    gc = hints.grammar_corrections[0]
    assert (gc.original, gc.corrected, gc.label) == ("I has", "I have", "subject_verb_agreement")
    assert hints.to_dict()["grammar_corrections"][0]["error_type"] == "subject_verb_agreement"
    assert len(accepted) == 1


def test_span_not_in_user_text_is_rejected():
    hints, accepted = EducationalHintsParser.corrections_from_diagnosis(
        None, [_diag("a toothache", "the toothache", "article_the")], "I have pain"
    )

    assert hints is None
    assert accepted == []


def test_span_match_ignores_case_width_and_whitespace():
    hints, accepted = EducationalHintsParser.corrections_from_diagnosis(
        None, [_diag("i  HAS", "I have")], "Ｉ has a cold"
    )

    assert hints is not None and len(accepted) == 1


def test_correction_equal_to_span_is_rejected():
    hints, accepted = EducationalHintsParser.corrections_from_diagnosis(
        None, [_diag("I need help", "i need  help")], "I need help with the toothache."
    )

    assert hints is None and accepted == []


def test_empty_span_or_correction_is_rejected():
    hints, accepted = EducationalHintsParser.corrections_from_diagnosis(
        None, [_diag("", "x"), _diag("I has", "")], "I has a cold"
    )

    assert hints is None and accepted == []


def test_unknown_label_becomes_other_and_alias_is_normalised():
    hints, _ = EducationalHintsParser.corrections_from_diagnosis(
        None,
        [_diag("I go", "I went", "tense"), _diag("a cold", "the cold", "vibes")],
        "I go and I have a cold",
    )

    assert [gc.label for gc in hints.grammar_corrections] == ["verb_tense", "other"]


def test_the_rules_explanation_is_no_longer_guessed_as_article():
    hints, _ = EducationalHintsParser.corrections_from_diagnosis(
        None,
        [_diag("rules", "the rules", "mystery", "Those are the rules of the clinic")],
        "Those are rules",
    )

    assert hints.grammar_corrections[0].label == "other"


def test_duplicate_errors_collapse_and_existing_vocab_hints_survive():
    base = EducationalHintsParser.parse("[\U0001F4DC 'menu' means a list.]")[1]
    hints, accepted = EducationalHintsParser.corrections_from_diagnosis(
        base, [_diag("I has", "I have"), _diag("I has", "I have")], "I has it"
    )

    assert len(hints.grammar_corrections) == 1 and len(accepted) == 1
    assert len(hints.vocabulary_hints) == 1


def test_no_errors_returns_hints_untouched():
    assert EducationalHintsParser.corrections_from_diagnosis(None, None, "hi") == (None, [])
    assert EducationalHintsParser.corrections_from_diagnosis(None, [], "hi") == (None, [])


def test_overlapping_spans_give_one_card_the_first():
    text = "I has a toothache since yesterday."
    errors = [
        _diag("has", "have", "subject_verb_agreement", "x"),
        _diag("I has", "I have had", "verb_tense", "y"),
        _diag("since yesterday", "since yesterday morning", "other", "z"),
    ]

    hints, accepted = EducationalHintsParser.corrections_from_diagnosis(None, errors, text)

    assert [gc.corrected for gc in hints.grammar_corrections] == ["have", "since yesterday morning"]
    assert len(accepted) == 2
