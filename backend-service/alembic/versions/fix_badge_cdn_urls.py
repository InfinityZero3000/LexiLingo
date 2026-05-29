"""fix badge CDN URLs

Revision ID: fix_badge_cdn_urls
Revises: add_fsrs_and_speaking_fields
Create Date: 2026-05-29 13:50:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "fix_badge_cdn_urls"
down_revision: Union[str, None] = "add_fsrs_and_speaking_fields"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


OLD_BADGE_CDN = (
    "https://cdn.jsdelivr.net/gh/InfinityZero3000/"
    "LexiLingo@feature/flutter-app/assets/badges/"
)
NEW_BADGE_CDN = (
    "https://cdn.jsdelivr.net/gh/InfinityZero3000/"
    "LexiLingo@main/flutter-app/assets/badges/"
)


def upgrade() -> None:
    bind = op.get_bind()
    bind.execute(
        sa.text(
            """
        UPDATE achievements
        SET badge_icon = replace(badge_icon, :old_cdn, :new_cdn)
        WHERE badge_icon LIKE :old_like
        """
        ),
        {
            "old_cdn": OLD_BADGE_CDN,
            "new_cdn": NEW_BADGE_CDN,
            "old_like": f"{OLD_BADGE_CDN}%",
        },
    )


def downgrade() -> None:
    bind = op.get_bind()
    bind.execute(
        sa.text(
            """
        UPDATE achievements
        SET badge_icon = replace(badge_icon, :new_cdn, :old_cdn)
        WHERE badge_icon LIKE :new_like
        """
        ),
        {
            "old_cdn": OLD_BADGE_CDN,
            "new_cdn": NEW_BADGE_CDN,
            "new_like": f"{NEW_BADGE_CDN}%",
        },
    )
