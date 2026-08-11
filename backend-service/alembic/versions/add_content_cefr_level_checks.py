"""add CEFR level CHECK constraints to content tables

Revision ID: content_cefr_level_checks
Revises: add_user_goal_interest
Create Date: 2026-08-07
"""

from collections.abc import Sequence

from alembic import op

revision: str = "content_cefr_level_checks"
down_revision: str | None = "add_user_goal_interest"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_CEFR = "('A1', 'A2', 'B1', 'B2', 'C1', 'C2')"


def upgrade() -> None:
    op.create_check_constraint(
        "ck_grammar_items_level_cefr", "grammar_items", f"level IN {_CEFR}"
    )
    op.create_check_constraint(
        "ck_question_bank_difficulty_level_cefr", "question_bank", f"difficulty_level IN {_CEFR}"
    )
    op.create_check_constraint(
        "ck_test_exams_level_cefr", "test_exams", f"level IN {_CEFR}"
    )


def downgrade() -> None:
    op.drop_constraint("ck_test_exams_level_cefr", "test_exams", type_="check")
    op.drop_constraint("ck_question_bank_difficulty_level_cefr", "question_bank", type_="check")
    op.drop_constraint("ck_grammar_items_level_cefr", "grammar_items", type_="check")
