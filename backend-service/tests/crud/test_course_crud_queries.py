from sqlalchemy import select
from sqlalchemy.dialects import postgresql, sqlite

from app.crud.course import _seed_first_ordering
from app.models.course import Course


def test_seed_first_ordering_uses_portable_sql():
    stmt = select(Course.id).order_by(_seed_first_ordering(), Course.created_at)

    sqlite_sql = str(stmt.compile(dialect=sqlite.dialect()))
    postgres_sql = str(stmt.compile(dialect=postgresql.dialect()))

    assert "@>" not in sqlite_sql
    assert "::jsonb" not in sqlite_sql
    assert "@>" not in postgres_sql
    assert "::jsonb" not in postgres_sql
    assert "LIKE" in sqlite_sql
    assert "LIKE" in postgres_sql
