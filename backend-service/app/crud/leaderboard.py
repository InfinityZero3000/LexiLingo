"""Shared leaderboard ranking helpers."""

from collections.abc import Iterable


def competition_ranks(scores: Iterable[int]) -> list[int]:
    """Return competition ranks for scores already ordered descending."""
    ranks: list[int] = []
    previous_score: int | None = None
    previous_rank = 0

    for position, score in enumerate(scores, start=1):
        if previous_score is None or score != previous_score:
            previous_rank = position
            previous_score = score
        ranks.append(previous_rank)

    return ranks


def competition_rank(score: int, all_scores: Iterable[int]) -> int:
    """Return a score's competition rank: one plus scores strictly above it."""
    return 1 + sum(candidate > score for candidate in all_scores)
