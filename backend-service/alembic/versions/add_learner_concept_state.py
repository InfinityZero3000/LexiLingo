"""add scalable learner concept state and observation outbox

Revision ID: add_learner_concept_state
Revises: add_mistake_notebook_entries
Create Date: 2026-07-12
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op
from app.core.db_types import GUID, PortableJSON, TZDateTime

revision: str = "add_learner_concept_state"
down_revision: str | None = "add_mistake_notebook_entries"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "learner_state_profiles",
        sa.Column("user_id", GUID(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("state_epoch", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("updated_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("state_epoch >= 0", name="ck_learner_state_profile_epoch"),
    )
    op.create_table(
        "learner_concept_states",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("user_id", GUID(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("concept_id", sa.String(255), nullable=False),
        sa.Column("mastery_probability", sa.Float(), nullable=False, server_default="0.5"),
        sa.Column("stability_days", sa.Float(), nullable=False, server_default="1.0"),
        sa.Column("difficulty", sa.Float(), nullable=False, server_default="0.5"),
        sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("correct_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("error_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_interacted_at", TZDateTime(), nullable=True),
        sa.Column("next_review_at", TZDateTime(), nullable=True),
        sa.Column("state_version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("algorithm_version", sa.String(32), nullable=False, server_default="bkt-fsrs-v1"),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "concept_id", name="uq_learner_state_user_concept"),
        sa.CheckConstraint("mastery_probability >= 0.0 AND mastery_probability <= 1.0", name="ck_learner_state_mastery_probability"),
        sa.CheckConstraint("difficulty >= 0.0 AND difficulty <= 1.0", name="ck_learner_state_difficulty"),
        sa.CheckConstraint("stability_days >= 0.0", name="ck_learner_state_stability"),
        sa.CheckConstraint("attempt_count >= 0 AND correct_count >= 0 AND error_count >= 0", name="ck_learner_state_counters_nonnegative"),
        sa.CheckConstraint("correct_count + error_count <= attempt_count", name="ck_learner_state_counter_consistency"),
        sa.CheckConstraint("state_version >= 1", name="ck_learner_state_version"),
    )
    op.create_index("ix_learner_state_user_due", "learner_concept_states", ["user_id", "next_review_at"])
    op.create_index("ix_learner_state_user_mastery", "learner_concept_states", ["user_id", "mastery_probability"])
    op.create_index("ix_learner_state_user_updated", "learner_concept_states", ["user_id", "updated_at"])

    op.create_table(
        "learner_observation_events",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("event_id", sa.String(64), nullable=False, unique=True),
        sa.Column("user_id", GUID(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("session_id", sa.String(255), nullable=True),
        sa.Column("concept_id", sa.String(255), nullable=False),
        sa.Column("outcome", sa.String(32), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("observed_at", TZDateTime(), nullable=False),
        sa.Column("payload", PortableJSON(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("available_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("claimed_at", TZDateTime(), nullable=True),
        sa.Column("applied_at", TZDateTime(), nullable=True),
        sa.Column("last_error_code", sa.String(100), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("confidence >= 0.0 AND confidence <= 1.0", name="ck_learner_observation_confidence"),
        sa.CheckConstraint("outcome IN ('correct', 'incorrect')", name="ck_learner_observation_outcome"),
        sa.CheckConstraint("status IN ('pending', 'processing', 'applied', 'retry', 'dead')", name="ck_learner_observation_status"),
        sa.CheckConstraint("attempt_count >= 0 AND attempt_count <= 100", name="ck_learner_observation_attempt_count"),
    )
    op.create_index("ix_learner_observation_claim", "learner_observation_events", ["status", "available_at", "created_at"])
    op.create_index("ix_learner_observation_cleanup", "learner_observation_events", ["status", "applied_at"])
    op.create_index("ix_learner_observation_user_created", "learner_observation_events", ["user_id", "created_at"])
    op.create_index("ix_learner_observation_concept_order", "learner_observation_events", ["user_id", "concept_id", "observed_at", "event_id"])


def downgrade() -> None:
    op.drop_index("ix_learner_observation_concept_order", table_name="learner_observation_events")
    op.drop_index("ix_learner_observation_user_created", table_name="learner_observation_events")
    op.drop_index("ix_learner_observation_cleanup", table_name="learner_observation_events")
    op.drop_index("ix_learner_observation_claim", table_name="learner_observation_events")
    op.drop_table("learner_observation_events")
    op.drop_index("ix_learner_state_user_updated", table_name="learner_concept_states")
    op.drop_index("ix_learner_state_user_mastery", table_name="learner_concept_states")
    op.drop_index("ix_learner_state_user_due", table_name="learner_concept_states")
    op.drop_table("learner_concept_states")
    op.drop_table("learner_state_profiles")
