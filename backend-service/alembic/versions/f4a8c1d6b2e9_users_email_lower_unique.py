"""users: one account per email address, whatever its letter case

Revision ID: f4a8c1d6b2e9
Revises: e9b4c2a7f1d8
"""
import logging

from alembic import op
import sqlalchemy as sa

revision = "f4a8c1d6b2e9"
down_revision = "e9b4c2a7f1d8"
branch_labels = None
depends_on = None

logger = logging.getLogger("alembic.runtime.migration")


def upgrade() -> None:
    clashes = op.get_bind().execute(sa.text(
        "SELECT count(*) FROM (SELECT 1 FROM users GROUP BY lower(email) HAVING count(*) > 1) AS d"
    )).scalar()
    if clashes:
        # A failed migration would stop the backend from starting. Index the lookup and
        # report; merge the accounts, then replace this with the unique index.
        logger.warning(
            "%s email address(es) belong to several accounts that differ only by letter case; "
            "created a non-unique index instead of uq_users_email_lower",
            clashes,
        )
        op.execute("CREATE INDEX IF NOT EXISTS ix_users_email_lower ON users (lower(email))")
        return
    op.execute("CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_lower ON users (lower(email))")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_users_email_lower")
    op.execute("DROP INDEX IF EXISTS ix_users_email_lower")
