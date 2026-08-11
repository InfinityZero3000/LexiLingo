"""Backfill is_verified for users created before email-verification enforcement

Revision ID: backfill_verified_users
Revises: 0d7ae4e272b7
Create Date: 2026-06-23

login/refresh now reject accounts with is_verified=False (see
app/routes/auth.py, commit 41613c45). Accounts registered before that
enforcement existed were never required to verify their email, so without
this backfill every pre-existing unverified local account would be locked
out on its next login attempt.
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "backfill_verified_users"
down_revision: Union[str, None] = "0d7ae4e272b7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Cutoff = author timestamp of commit 41613c45 ("fix(auth): block
# login/refresh for unverified email accounts"). Users registered at or
# after this point were always subject to the enforcement and must verify
# normally.
ENFORCEMENT_CUTOFF = "2026-06-23T11:48:46+07:00"


def upgrade() -> None:
    op.execute(
        f"""
        UPDATE users
        SET is_verified = TRUE
        WHERE is_verified = FALSE
          AND created_at < TIMESTAMP WITH TIME ZONE '{ENFORCEMENT_CUTOFF}'
        """
    )


def downgrade() -> None:
    # Backfill is one-directional by design — there is no reliable way to
    # tell which legacy users were "really" unverified vs. grandfathered in.
    pass
