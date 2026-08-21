"""add IELTS mock test, attempt and grading tables

Revision ID: d5e91f3a7c62
Revises: c3f8a2d5e714
Create Date: 2026-08-20

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.core.db_types import GUID, TZDateTime, PortableJSON

revision: str = "d5e91f3a7c62"
down_revision: Union[str, None] = "c3f8a2d5e714"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "ielts_tests",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("slug", sa.String(255), nullable=True, unique=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("test_type", sa.String(20), nullable=False, server_default="academic"),
        sa.Column("skill_scope", sa.String(20), nullable=False, server_default="full"),
        sa.Column("target_band", sa.String(20), nullable=True),
        sa.Column("content", PortableJSON(), nullable=True),
        sa.Column("is_published", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_by", GUID(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint(
            "test_type IN ('academic', 'general_training')",
            name="ck_ielts_tests_test_type",
        ),
        sa.CheckConstraint(
            "skill_scope IN ('full', 'listening', 'reading', 'writing', 'speaking')",
            name="ck_ielts_tests_skill_scope",
        ),
    )
    op.create_index("ix_ielts_tests_published", "ielts_tests", ["is_published"])
    op.create_index("ix_ielts_tests_type_scope", "ielts_tests", ["test_type", "skill_scope"])

    op.create_table(
        "ielts_attempts",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("user_id", GUID(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("test_id", GUID(), sa.ForeignKey("ielts_tests.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="in_progress"),
        sa.Column("skill_scope", sa.String(20), nullable=False, server_default="full"),
        sa.Column("answers", PortableJSON(), nullable=True),
        sa.Column("raw_scores", PortableJSON(), nullable=True),
        sa.Column("listening_band", sa.Numeric(2, 1), nullable=True),
        sa.Column("reading_band", sa.Numeric(2, 1), nullable=True),
        sa.Column("writing_band", sa.Numeric(2, 1), nullable=True),
        sa.Column("speaking_band", sa.Numeric(2, 1), nullable=True),
        sa.Column("overall_band", sa.Numeric(2, 1), nullable=True),
        sa.Column("time_spent_seconds", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("started_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("submitted_at", TZDateTime(), nullable=True),
        sa.Column("graded_at", TZDateTime(), nullable=True),
        sa.CheckConstraint(
            "status IN ('in_progress', 'submitted', 'graded', 'abandoned')",
            name="ck_ielts_attempts_status",
        ),
        sa.CheckConstraint(
            "skill_scope IN ('full', 'listening', 'reading', 'writing', 'speaking')",
            name="ck_ielts_attempts_skill_scope",
        ),
    )
    op.create_index("ix_ielts_attempts_user_started", "ielts_attempts", ["user_id", "started_at"])
    op.create_index("ix_ielts_attempts_test", "ielts_attempts", ["test_id"])

    op.create_table(
        "ielts_gradings",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("attempt_id", GUID(), sa.ForeignKey("ielts_attempts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("skill", sa.String(20), nullable=False),
        sa.Column("part_key", sa.String(50), nullable=False),
        sa.Column("submission_text", sa.Text(), nullable=True),
        sa.Column("word_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("criteria_scores", PortableJSON(), nullable=True),
        sa.Column("band", sa.Numeric(2, 1), nullable=True),
        sa.Column("feedback", PortableJSON(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("error_detail", sa.Text(), nullable=True),
        sa.Column("grader_version", sa.String(50), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("graded_at", TZDateTime(), nullable=True),
        sa.CheckConstraint("skill IN ('writing', 'speaking')", name="ck_ielts_gradings_skill"),
        sa.CheckConstraint(
            "status IN ('pending', 'graded', 'failed')", name="ck_ielts_gradings_status"
        ),
    )
    op.create_index("ix_ielts_gradings_attempt", "ielts_gradings", ["attempt_id"])
    op.create_index("ix_ielts_gradings_status", "ielts_gradings", ["status"])


def downgrade() -> None:
    op.drop_table("ielts_gradings")
    op.drop_table("ielts_attempts")
    op.drop_table("ielts_tests")
