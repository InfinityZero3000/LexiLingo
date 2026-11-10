"""Account deletion must reach every table that points at users.id.

permanently_delete_user wipes a hand-kept list of models and then deletes the
user row. A table missing from that list is only safe if the database removes
its rows itself, so any other FK to users.id would fail the delete in
production (SQLite, which the tests use, does not enforce it).
"""
import app.models  # noqa: F401  (registers every table on Base.metadata)
from app.core.database import Base
from app.models.gamification import UserFollowing
from app.services.user_deletion_service import _USER_ID_SCOPED_MODELS

_HANDLED = {m.__table__.name for m in _USER_ID_SCOPED_MODELS} | {
    UserFollowing.__table__.name,
    "users",
}


def test_every_user_foreign_key_is_deleted_or_cascaded() -> None:
    uncovered = []
    for table in Base.metadata.sorted_tables:
        if table.name in _HANDLED:
            continue
        for column in table.columns:
            for fk in column.foreign_keys:
                if fk.column.table.name != "users":
                    continue
                if (fk.ondelete or "").upper() not in ("CASCADE", "SET NULL"):
                    uncovered.append(f"{table.name}.{column.name}")

    assert not uncovered, (
        "add these to _USER_ID_SCOPED_MODELS or give the FK ondelete=CASCADE/SET NULL: "
        + ", ".join(sorted(uncovered))
    )
