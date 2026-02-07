"""Add content lab tables and seed RBAC roles

Revision ID: add_admin_content_and_seed_roles
Revises: add_rbac_system
Create Date: 2026-02-06
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision = "add_admin_content_and_seed_roles"
down_revision = "add_rbac_system"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Seed roles (user, admin, super_admin)
    op.execute(
        """
        INSERT INTO roles (id, name, slug, description, level, is_system, is_active, created_at, updated_at)
        VALUES
          ('00000000-0000-0000-0000-000000000001', 'User', 'user', 'Default user role', 0, true, true, now(), now()),
          ('00000000-0000-0000-0000-000000000002', 'Admin', 'admin', 'Admin role', 1, true, true, now(), now()),
          ('00000000-0000-0000-0000-000000000003', 'Super Admin', 'super_admin', 'Super admin role', 2, true, true, now(), now())
        ON CONFLICT (slug) DO NOTHING;
        """
    )

    # Grammar items
    op.create_table(
        "grammar_items",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("level", sa.String(20), nullable=False, server_default="A1"),
        sa.Column("topic", sa.String(100), nullable=True),
        sa.Column("summary", sa.String(500), nullable=True),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("examples", sa.JSON(), nullable=True),
        sa.Column("tags", sa.JSON(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_grammar_items_level", "grammar_items", ["level"])
    op.create_index("ix_grammar_items_topic", "grammar_items", ["topic"])

    # Question bank
    op.create_table(
        "question_bank",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("prompt", sa.Text(), nullable=False),
        sa.Column("question_type", sa.String(50), nullable=False, server_default="mcq"),
        sa.Column("options", sa.JSON(), nullable=True),
        sa.Column("answer", sa.JSON(), nullable=True),
        sa.Column("explanation", sa.Text(), nullable=True),
        sa.Column("difficulty_level", sa.String(20), nullable=False, server_default="A1"),
        sa.Column("tags", sa.JSON(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("grammar_id", UUID(as_uuid=True), sa.ForeignKey("grammar_items.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_question_bank_level", "question_bank", ["difficulty_level"])
    op.create_index("ix_question_bank_type", "question_bank", ["question_type"])
    op.create_index("ix_question_bank_grammar_id", "question_bank", ["grammar_id"])

    # Test exams
    op.create_table(
        "test_exams",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("level", sa.String(20), nullable=False, server_default="A1"),
        sa.Column("duration_minutes", sa.Integer(), nullable=False, server_default="20"),
        sa.Column("passing_score", sa.Integer(), nullable=False, server_default="70"),
        sa.Column("question_ids", sa.JSON(), nullable=True),
        sa.Column("is_published", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_test_exams_level", "test_exams", ["level"])
    op.create_index("ix_test_exams_published", "test_exams", ["is_published"])


def downgrade() -> None:
    op.drop_index("ix_test_exams_published", table_name="test_exams")
    op.drop_index("ix_test_exams_level", table_name="test_exams")
    op.drop_table("test_exams")

    op.drop_index("ix_question_bank_grammar_id", table_name="question_bank")
    op.drop_index("ix_question_bank_type", table_name="question_bank")
    op.drop_index("ix_question_bank_level", table_name="question_bank")
    op.drop_table("question_bank")

    op.drop_index("ix_grammar_items_topic", table_name="grammar_items")
    op.drop_index("ix_grammar_items_level", table_name="grammar_items")
    op.drop_table("grammar_items")

    # Do not delete roles on downgrade
