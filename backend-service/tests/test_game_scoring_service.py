import pytest

from app.services.game_scoring_service import (
    DuplicateAnswerError,
    GameScoringError,
    UnknownAnswerError,
    score_game,
)


@pytest.fixture
def expected_items():
    return [
        {"id": "q1", "answer": "cat", "xp_value": 5},
        {"id": "q2", "answer": "dog", "xp_value": 10},
    ]


@pytest.mark.parametrize(
    "game_type",
    [
        "word_scramble",
        "fill_blank",
        "matching",
        "spelling_bee",
        "grammar_quiz",
    ],
)
def test_scores_verified_answers_for_standard_games(game_type, expected_items):
    result = score_game(
        game_type=game_type,
        expected_items=expected_items,
        submitted_answers=[
            {"id": "q1", "answer": " CAT "},
            {"id": "q2", "answer": "wrong"},
        ],
    )

    assert result.correct_count == 1
    assert result.total_count == 2
    assert result.raw_xp == 5
    assert result.penalties == 0
    assert result.final_base_xp == 5


def test_rejects_missing_answer(expected_items):
    with pytest.raises(GameScoringError, match="answer count"):
        score_game(
            game_type="grammar_quiz",
            expected_items=expected_items,
            submitted_answers=[{"id": "q1", "answer": "cat"}],
        )


def test_zero_correct_answers_awards_zero_xp(expected_items):
    result = score_game(
        game_type="matching",
        expected_items=expected_items,
        submitted_answers=[
            {"id": "q1", "answer": "wrong"},
            {"id": "q2", "answer": "wrong"},
        ],
    )

    assert result.correct_count == 0
    assert result.final_base_xp == 0


def test_empty_answers_are_valid_incorrect_submissions(expected_items):
    result = score_game(
        game_type="grammar_quiz",
        expected_items=expected_items,
        submitted_answers=[
            {"id": "q1", "answer": ""},
            {"id": "q2", "answer": ""},
        ],
    )

    assert result.correct_count == 0
    assert result.total_count == 2


def test_hangman_awards_only_for_verified_win():
    expected = [{"id": "word", "answer": "adventure", "xp_value": 20}]

    loss = score_game(
        game_type="hangman",
        expected_items=expected,
        submitted_answers=[{"id": "word", "answer": "wrong"}],
        hint_penalty=5,
    )
    win = score_game(
        game_type="hangman",
        expected_items=expected,
        submitted_answers=[{"id": "word", "answer": "Adventure"}],
        hint_penalty=5,
    )

    assert loss.final_base_xp == 0
    assert win.raw_xp == 20
    assert win.penalties == 5
    assert win.final_base_xp == 15


def test_hint_penalty_cannot_make_xp_negative():
    result = score_game(
        game_type="hangman",
        expected_items=[{"id": "word", "answer": "cat", "xp_value": 5}],
        submitted_answers=[{"id": "word", "answer": "cat"}],
        hint_penalty=20,
    )

    assert result.final_base_xp == 0


def test_rejects_unknown_game_type(expected_items):
    with pytest.raises(GameScoringError, match="Unsupported game type"):
        score_game(
            game_type="memory",
            expected_items=expected_items,
            submitted_answers=[],
        )


def test_rejects_duplicate_submitted_ids(expected_items):
    with pytest.raises(DuplicateAnswerError):
        score_game(
            game_type="fill_blank",
            expected_items=expected_items,
            submitted_answers=[
                {"id": "q1", "answer": "cat"},
                {"id": "q1", "answer": "cat"},
            ],
        )


def test_rejects_unknown_submitted_id(expected_items):
    with pytest.raises(UnknownAnswerError):
        score_game(
            game_type="fill_blank",
            expected_items=expected_items,
            submitted_answers=[{"id": "tampered", "answer": "cat"}],
        )


@pytest.mark.parametrize(
    "expected_items",
    [
        [],
        [{"id": "q1", "answer": "cat", "xp_value": -1}],
        [{"id": "q1", "answer": "cat", "xp_value": 5}, {"id": "q1", "answer": "dog", "xp_value": 5}],
    ],
)
def test_rejects_invalid_server_session_data(expected_items):
    with pytest.raises(GameScoringError):
        score_game(
            game_type="word_scramble",
            expected_items=expected_items,
            submitted_answers=[],
        )


def test_rejects_negative_hint_penalty(expected_items):
    with pytest.raises(GameScoringError, match="Hint penalty"):
        score_game(
            game_type="hangman",
            expected_items=expected_items,
            submitted_answers=[],
            hint_penalty=-1,
        )
