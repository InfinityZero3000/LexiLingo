"""Server-authoritative scoring rules for game session completion."""

from dataclasses import dataclass
from typing import Any, Mapping, Sequence


SUPPORTED_GAME_TYPES = {
    "word_scramble",
    "fill_blank",
    "matching",
    "spelling_bee",
    "grammar_quiz",
    "hangman",
}


class GameScoringError(ValueError):
    """Raised when game or session scoring data is invalid."""


class DuplicateAnswerError(GameScoringError):
    """Raised when an answer identifier appears more than once."""


class UnknownAnswerError(GameScoringError):
    """Raised when the client submits an identifier outside the session."""


@dataclass(frozen=True)
class GameScore:
    correct_count: int
    total_count: int
    raw_xp: int
    penalties: int
    final_base_xp: int
    incorrect_ids: frozenset[str]


def _normalize_answer(value: Any) -> str:
    return str(value or "").strip().casefold()


def _validated_expected_items(
    expected_items: Sequence[Mapping[str, Any]],
) -> dict[str, Mapping[str, Any]]:
    if not expected_items:
        raise GameScoringError("Session must contain at least one expected item")

    indexed: dict[str, Mapping[str, Any]] = {}
    for item in expected_items:
        item_id = str(item.get("id") or "").strip()
        xp_value = item.get("xp_value")
        if not item_id:
            raise GameScoringError("Expected item is missing an id")
        if item_id in indexed:
            raise GameScoringError(f"Duplicate expected item id: {item_id}")
        if (
            isinstance(xp_value, bool)
            or not isinstance(xp_value, int)
            or xp_value < 0
        ):
            raise GameScoringError(f"Invalid XP value for item: {item_id}")
        if "answer" not in item:
            raise GameScoringError(f"Expected item is missing an answer: {item_id}")
        indexed[item_id] = item
    return indexed


def _validated_submitted_answers(
    submitted_answers: Sequence[Mapping[str, Any]],
    expected_by_id: Mapping[str, Mapping[str, Any]],
) -> dict[str, str]:
    indexed: dict[str, str] = {}
    for item in submitted_answers:
        item_id = str(item.get("id") or "").strip()
        if not item_id or item_id not in expected_by_id:
            raise UnknownAnswerError(f"Unknown answer id: {item_id or '<empty>'}")
        if item_id in indexed:
            raise DuplicateAnswerError(f"Duplicate submitted answer id: {item_id}")
        indexed[item_id] = _normalize_answer(item.get("answer"))
    return indexed


def score_game(
    *,
    game_type: str,
    expected_items: Sequence[Mapping[str, Any]],
    submitted_answers: Sequence[Mapping[str, Any]],
    hint_penalty: int = 0,
) -> GameScore:
    """Verify submitted answers against a persisted game-session snapshot."""
    if game_type not in SUPPORTED_GAME_TYPES:
        raise GameScoringError(f"Unsupported game type: {game_type}")
    if (
        isinstance(hint_penalty, bool)
        or not isinstance(hint_penalty, int)
        or hint_penalty < 0
    ):
        raise GameScoringError("Hint penalty must be a non-negative integer")

    expected_by_id = _validated_expected_items(expected_items)
    submitted_by_id = _validated_submitted_answers(
        submitted_answers,
        expected_by_id,
    )
    if len(submitted_by_id) != len(expected_by_id):
        raise GameScoringError(
            "Submitted answer count does not match the game session"
        )

    correct_count = 0
    raw_xp = 0
    incorrect_ids: set[str] = set()
    for item_id, expected in expected_by_id.items():
        submitted = submitted_by_id.get(item_id)
        is_correct = (
            submitted is not None
            and submitted == _normalize_answer(expected["answer"])
        )
        if is_correct:
            correct_count += 1
            raw_xp += int(expected["xp_value"])
        else:
            incorrect_ids.add(item_id)

    penalties = hint_penalty if game_type == "hangman" and correct_count else 0
    final_base_xp = max(0, raw_xp - penalties)

    return GameScore(
        correct_count=correct_count,
        total_count=len(expected_by_id),
        raw_xp=raw_xp,
        penalties=penalties,
        final_base_xp=final_base_xp,
        incorrect_ids=frozenset(incorrect_ids),
    )
