"""ops_error_groups and ops_error_counts: grouped errors for the admin view and email reports

Revision ID: a7c3e9d2b4f1
Revises: f4a8c1d6b2e9
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "a7c3e9d2b4f1"
down_revision = "f4a8c1d6b2e9"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ops_error_groups",
        sa.Column("fingerprint", sa.String(40), primary_key=True),
        sa.Column("service", sa.String(30), nullable=False),
        sa.Column("kind", sa.String(10), nullable=False),
        sa.Column("method", sa.String(10), nullable=False),
        sa.Column("route", sa.String(300), nullable=False),
        sa.Column("status_code", sa.Integer(), nullable=False),
        sa.Column("error_type", sa.String(150), nullable=True),
        sa.Column("location", sa.String(200), nullable=True),
        sa.Column("sample_message", sa.Text(), nullable=True),
        sa.Column("sample_request_id", sa.String(100), nullable=True),
        sa.Column("first_seen", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_seen", sa.DateTime(timezone=True), nullable=False),
        sa.Column("total_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("reported_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("state", sa.String(10), nullable=False, server_default="open"),
        sa.Column("regressed", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "state_changed_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("state_changed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_ops_error_groups_last_seen", "ops_error_groups", ["last_seen"])
    op.create_table(
        "ops_error_counts",
        sa.Column(
            "fingerprint",
            sa.String(40),
            sa.ForeignKey("ops_error_groups.fingerprint", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("bucket_start", sa.DateTime(timezone=True), primary_key=True),
        sa.Column("count", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade() -> None:
    op.drop_table("ops_error_counts")
    op.drop_index("ix_ops_error_groups_last_seen", table_name="ops_error_groups")
    op.drop_table("ops_error_groups")
