from app.crud.leaderboard import competition_rank, competition_ranks


def test_competition_ranking_keeps_ties_and_skips_positions():
    assert competition_ranks([100, 100, 80, 50, 50]) == [1, 1, 3, 4, 4]


def test_list_rank_and_current_user_rank_use_same_policy():
    scores = [120, 100, 100, 40]
    listed_ranks = competition_ranks(scores)

    assert competition_rank(100, scores) == 2
    assert listed_ranks[1] == listed_ranks[2] == 2


def test_empty_leaderboard_has_no_ranks():
    assert competition_ranks([]) == []
