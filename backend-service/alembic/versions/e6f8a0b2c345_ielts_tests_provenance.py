"""ielts_tests.provenance: where each reading passage came from

Revision ID: e6f8a0b2c345
Revises: c4d6e8f0a123
Create Date: 2026-11-16
"""

from __future__ import annotations

import json
from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "e6f8a0b2c345"
down_revision: str | None = "c4d6e8f0a123"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# scripts/ielts_paper_academic_1.py: written from scratch, fictional sources.
_GENERATED_SLUG = "ielts-academic-practice-test-1"
_GENERATED = {
    "passages": [
        {"section": f"reading:{n}", "title": title, "license_id": "LicenseRef-Generated"}
        for n, title in enumerate(
            (
                "The Return of the Urban Beehive",
                "Cooling the City",
                "The Measurement of Happiness",
            ),
            start=1,
        )
    ],
    "generator": {"script": "scripts/ielts_paper_academic_1.py"},
}


def upgrade() -> None:
    op.add_column("ielts_tests", sa.Column("provenance", postgresql.JSONB(), nullable=True))
    op.get_bind().execute(
        sa.text(
            "UPDATE ielts_tests SET provenance = CAST(:p AS jsonb) "
            "WHERE slug = :slug AND provenance IS NULL"
        ),
        {"p": json.dumps(_GENERATED), "slug": _GENERATED_SLUG},
    )


def downgrade() -> None:
    op.drop_column("ielts_tests", "provenance")
