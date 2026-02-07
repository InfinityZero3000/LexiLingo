"""Add RBAC system and missing columns

- Create roles, permissions, role_permissions, audit_logs tables
- Add role_id FK to users
- Add slug column to achievements
- Add FK constraints to user_devices, refresh_tokens

Revision ID: add_rbac_system
Revises: 49b1f1d9b26c
Create Date: 2026-02-07
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


revision = "add_rbac_system"
down_revision = "49b1f1d9b26c"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1. Create roles table ──────────────────────────────────
    op.create_table(
        "roles",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(50), nullable=False, unique=True),
        sa.Column("slug", sa.String(50), nullable=False, unique=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("level", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_system", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_roles_slug", "roles", ["slug"])

    # ── 2. Create permissions table ────────────────────────────
    op.create_table(
        "permissions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(100), nullable=False, unique=True),
        sa.Column("slug", sa.String(100), nullable=False, unique=True),
        sa.Column("resource", sa.String(50), nullable=False),
        sa.Column("action", sa.String(50), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_permissions_slug", "permissions", ["slug"])
    op.create_index("ix_permissions_resource", "permissions", ["resource"])
    op.create_index("idx_permission_resource_action", "permissions", ["resource", "action"], unique=True)

    # ── 3. Create role_permissions junction table ──────────────
    op.create_table(
        "role_permissions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("role_id", UUID(as_uuid=True), sa.ForeignKey("roles.id", ondelete="CASCADE"), nullable=False),
        sa.Column("permission_id", UUID(as_uuid=True), sa.ForeignKey("permissions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("granted_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_role_permissions_role_id", "role_permissions", ["role_id"])
    op.create_index("ix_role_permissions_permission_id", "role_permissions", ["permission_id"])
    op.create_index("idx_role_permission_unique", "role_permissions", ["role_id", "permission_id"], unique=True)

    # ── 4. Create audit_logs table ─────────────────────────────
    op.create_table(
        "audit_logs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("action", sa.String(50), nullable=False),
        sa.Column("resource_type", sa.String(50), nullable=False),
        sa.Column("resource_id", sa.String(255), nullable=True),
        sa.Column("details", sa.Text(), nullable=True),
        sa.Column("ip_address", sa.String(50), nullable=True),
        sa.Column("user_agent", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_audit_logs_user_id", "audit_logs", ["user_id"])
    op.create_index("ix_audit_logs_resource_type", "audit_logs", ["resource_type"])
    op.create_index("idx_audit_user_action", "audit_logs", ["user_id", "action"])
    op.create_index("idx_audit_resource", "audit_logs", ["resource_type", "resource_id"])
    op.create_index("ix_audit_logs_created_at", "audit_logs", ["created_at"])

    # ── 5. Add role_id FK to users ─────────────────────────────
    op.add_column("users", sa.Column("role_id", UUID(as_uuid=True), nullable=True))
    op.create_foreign_key("fk_users_role_id", "users", "roles", ["role_id"], ["id"], ondelete="SET NULL")
    op.create_index("ix_users_role_id", "users", ["role_id"])

    # ── 6. Add slug column to achievements ─────────────────────
    op.add_column("achievements", sa.Column("slug", sa.String(100), nullable=True))
    op.create_unique_constraint("uq_achievements_slug", "achievements", ["slug"])

    # ── 7. Add FK constraints to user_devices and refresh_tokens
    op.create_foreign_key(
        "fk_user_devices_user_id", "user_devices", "users",
        ["user_id"], ["id"], ondelete="CASCADE"
    )
    op.create_foreign_key(
        "fk_refresh_tokens_user_id", "refresh_tokens", "users",
        ["user_id"], ["id"], ondelete="CASCADE"
    )

    # ── 8. Add FK to notifications (table exists, no FK) ───────
    op.create_foreign_key(
        "fk_notifications_user_id", "notifications", "users",
        ["user_id"], ["id"], ondelete="CASCADE"
    )
    op.create_index("idx_notification_user_read", "notifications", ["user_id", "is_read"])


def downgrade() -> None:
    # Remove notification FK & index
    op.drop_index("idx_notification_user_read", table_name="notifications")
    op.drop_constraint("fk_notifications_user_id", "notifications", type_="foreignkey")

    # Remove FK constraints from user_devices and refresh_tokens
    op.drop_constraint("fk_refresh_tokens_user_id", "refresh_tokens", type_="foreignkey")
    op.drop_constraint("fk_user_devices_user_id", "user_devices", type_="foreignkey")

    # Remove slug from achievements
    op.drop_constraint("uq_achievements_slug", "achievements", type_="unique")
    op.drop_column("achievements", "slug")

    # Remove role_id from users
    op.drop_index("ix_users_role_id", table_name="users")
    op.drop_constraint("fk_users_role_id", "users", type_="foreignkey")
    op.drop_column("users", "role_id")

    # Drop tables in reverse order
    op.drop_table("audit_logs")
    op.drop_table("role_permissions")
    op.drop_table("permissions")
    op.drop_table("roles")
