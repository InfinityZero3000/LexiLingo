from app.services import TRIGGER_CONDITIONS


def test_game_completion_checks_game_xp_level_and_streak_achievements():
    assert TRIGGER_CONDITIONS["game_complete"] == [
        "game_complete",
        "xp_earned",
        "numeric_level",
        "reach_streak",
    ]
