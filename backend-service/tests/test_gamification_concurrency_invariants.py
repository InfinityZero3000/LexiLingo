"""Static guards for race-safety invariants in gamification writes."""

import ast
from pathlib import Path


ROOT = Path(__file__).parents[1]


def _function_calls(path: str, function_name: str, class_name: str | None = None) -> set[str]:
    tree = ast.parse((ROOT / path).read_text())
    scope = tree.body
    if class_name:
        scope = next(
            node.body
            for node in tree.body
            if isinstance(node, ast.ClassDef) and node.name == class_name
        )
    function = next(
        node for node in scope
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == function_name
    )
    return {
        node.func.attr
        for node in ast.walk(function)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }


def test_gamification_updates_lock_rows_and_claim_is_idempotent() -> None:
    assert "with_for_update" in _function_calls(
        "app/crud/gamification.py", "add_gems", "WalletCRUD"
    )
    assert "with_for_update" in _function_calls(
        "app/crud/gamification.py", "get_or_create_entry", "LeaderboardCRUD"
    )
    assert "with_for_update" in _function_calls(
        "app/crud/gamification.py", "add_xp", "LeaderboardCRUD"
    )
    claim_calls = _function_calls(
        "app/routes/challenges.py", "claim_challenge_reward"
    )
    assert {"begin_nested", "flush", "with_for_update"} <= claim_calls
    bonus_calls = _function_calls(
        "app/routes/challenges.py", "claim_daily_bonus"
    )
    assert {"begin_nested", "flush", "with_for_update"} <= bonus_calls
    migration = (ROOT / "alembic/versions/add_challenge_reward_claim_unique.py").read_text()
    assert "create_unique_constraint" in migration
    assert '["user_id", "challenge_id", "claim_date"]' in migration
