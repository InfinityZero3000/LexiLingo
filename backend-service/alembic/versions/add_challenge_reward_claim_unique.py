"""add challenge reward claim uniqueness

Revision ID: challenge_claim_unique
Revises: add_learner_concept_state
Create Date: 2026-08-02
"""

from collections.abc import Sequence

from alembic import op

revision: str = "challenge_claim_unique"
down_revision: str | None = "add_learner_concept_state"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_unique_constraint(
        "uq_challenge_reward_claim_user_challenge_date",
        "challenge_reward_claims",
        ["user_id", "challenge_id", "claim_date"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_challenge_reward_claim_user_challenge_date",
        "challenge_reward_claims",
        type_="unique",
    )
