import pytest

from app.services.rank_service import (
    RANK_THRESHOLDS,
    RankTier,
    calculate_rank,
    calculate_rank_score,
    check_rank_change,
)
from app.routes.gamification import (
    is_in_demotion_zone,
    is_in_promotion_zone,
)


@pytest.mark.parametrize(
    ("numeric_level", "cefr", "expected"),
    [
        (1, "A1", RankTier.BRONZE),
        (23, "A1", RankTier.SILVER),
        (37, "A2", RankTier.GOLD),
        (50, "B1", RankTier.PLATINUM),
        (56, "B2", RankTier.SAPPHIRE),
        (73, "B2", RankTier.RUBY),
        (67, "C2", RankTier.AMETHYST),
        (92, "C2", RankTier.MASTER),
    ],
)
def test_rank_tiers_cover_every_threshold(numeric_level, cefr, expected):
    assert calculate_rank(numeric_level, cefr).rank is expected


def test_numeric_level_is_clamped_to_zero_and_one_hundred():
    assert calculate_rank_score(-10, "A1") == calculate_rank_score(0, "A1")
    assert calculate_rank_score(999, "C2") == 100.0


def test_invalid_cefr_falls_back_to_a1():
    assert calculate_rank_score(40, "invalid") == calculate_rank_score(40, "A1")


def test_thresholds_are_contiguous():
    for current, following in zip(RANK_THRESHOLDS, RANK_THRESHOLDS[1:]):
        assert current[3] == following[2]


def test_rank_change_distinguishes_promotion_demotion_and_unchanged():
    promotion = check_rank_change(1, "A1", 100, "C2")
    demotion = check_rank_change(100, "C2", 1, "A1")
    unchanged = check_rank_change(1, "A1", 2, "A1")

    assert promotion.direction == "promotion"
    assert promotion.changed is True
    assert demotion.direction == "demotion"
    assert demotion.changed is True
    assert unchanged.direction == "unchanged"
    assert unchanged.changed is False


def test_league_zones_use_actual_participant_count_without_overlap():
    assert is_in_promotion_zone(3, 10) is True
    assert is_in_promotion_zone(4, 10) is False
    assert is_in_demotion_zone(8, 10) is True
    assert is_in_demotion_zone(7, 10) is False
    assert is_in_demotion_zone(3, 3) is False
