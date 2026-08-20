"""The observation payload allowlist is duplicated across two services.

ai-service spools observations, the backend validates them, and an unknown key
rejects the whole batch — so a key added on one side only silently drops every
observation from the other. The comment saying "keep in sync by hand" is not
enforcement; this is.
"""

import ast
import pathlib

import pytest

from app.schemas.learner_state import ALLOWED_OBSERVATION_PAYLOAD_KEYS

AI_SPOOL = (
    pathlib.Path(__file__).resolve().parents[2]
    / "ai-service"
    / "api"
    / "services"
    / "learner_observation_spool.py"
)


def _set_literal(path: pathlib.Path, name: str) -> set[str]:
    tree = ast.parse(path.read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == name
            for target in node.targets
        ):
            return set(ast.literal_eval(node.value))
    raise AssertionError(f"{name} not found in {path}")


def test_ai_service_allowlist_matches_backend():
    if not AI_SPOOL.exists():
        pytest.skip("ai-service source not checked out alongside backend-service")

    ai_keys = _set_literal(AI_SPOOL, "_ALLOWED_PAYLOAD_KEYS")

    assert ai_keys == ALLOWED_OBSERVATION_PAYLOAD_KEYS, (
        "Observation payload allowlists drifted.\n"
        f"  only in ai-service: {sorted(ai_keys - ALLOWED_OBSERVATION_PAYLOAD_KEYS)}\n"
        f"  only in backend:    {sorted(ALLOWED_OBSERVATION_PAYLOAD_KEYS - ai_keys)}"
    )
