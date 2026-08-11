"""Schema contract tests for scalable learner state persistence."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

from sqlalchemy import CheckConstraint, UniqueConstraint

from app.core.database import Base
from app.models import (  # noqa: F401 - imports register tables in metadata
    LearnerConceptState,
    LearnerObservationEvent,
    LearnerStateProfile,
)


def _unique_column_sets(table) -> set[frozenset[str]]:
    return {
        frozenset(constraint.columns.keys())
        for constraint in table.constraints
        if isinstance(constraint, UniqueConstraint)
    }


def _check_names(table) -> set[str]:
    return {
        constraint.name
        for constraint in table.constraints
        if isinstance(constraint, CheckConstraint) and constraint.name
    }


def test_learner_state_schema_is_sparse_versioned_and_idempotent() -> None:
    state = Base.metadata.tables["learner_concept_states"]
    profile = Base.metadata.tables["learner_state_profiles"]
    events = Base.metadata.tables["learner_observation_events"]

    assert {
        "user_id",
        "concept_id",
        "mastery_probability",
        "stability_days",
        "difficulty",
        "state_version",
    } <= set(state.c.keys())
    assert frozenset({"user_id", "concept_id"}) in _unique_column_sets(state)
    assert profile.c.user_id.primary_key is True
    assert profile.c.state_epoch.nullable is False
    assert events.c.event_id.unique is True
    assert {"status", "available_at", "claimed_at", "applied_at"} <= set(events.c.keys())
    assert {
        "ck_learner_state_mastery_probability",
        "ck_learner_state_difficulty",
        "ck_learner_state_stability",
        "ck_learner_state_counters_nonnegative",
        "ck_learner_state_counter_consistency",
        "ck_learner_state_version",
    } <= _check_names(state)
    assert "ck_learner_state_profile_epoch" in _check_names(profile)
    assert {
        "ck_learner_observation_confidence",
        "ck_learner_observation_outcome",
        "ck_learner_observation_status",
        "ck_learner_observation_attempt_count",
    } <= _check_names(events)


def test_learner_state_schema_has_bounded_query_and_outbox_indexes() -> None:
    state = Base.metadata.tables["learner_concept_states"]
    events = Base.metadata.tables["learner_observation_events"]

    state_indexes = {index.name: tuple(index.columns.keys()) for index in state.indexes}
    event_indexes = {index.name: tuple(index.columns.keys()) for index in events.indexes}

    assert state_indexes["ix_learner_state_user_due"] == ("user_id", "next_review_at")
    assert state_indexes["ix_learner_state_user_mastery"] == (
        "user_id",
        "mastery_probability",
    )
    assert state_indexes["ix_learner_state_user_updated"] == ("user_id", "updated_at")
    assert event_indexes["ix_learner_observation_claim"] == (
        "status",
        "available_at",
        "created_at",
    )
    assert event_indexes["ix_learner_observation_cleanup"] == ("status", "applied_at")
    assert event_indexes["ix_learner_observation_user_created"] == (
        "user_id",
        "created_at",
    )


def test_learner_state_foreign_keys_cascade_with_the_user() -> None:
    """Per-user overlays and pending events must not survive user deletion."""
    for table_name in (
        "learner_concept_states",
        "learner_state_profiles",
        "learner_observation_events",
    ):
        table = Base.metadata.tables[table_name]
        user_fk = next(iter(table.c.user_id.foreign_keys))

        assert user_fk.target_fullname == "users.id"
        assert user_fk.ondelete == "CASCADE"


def test_migration_creates_the_same_tables_and_indexes_as_the_models(monkeypatch) -> None:
    """Catch drift where ORM tests pass but the deployed Alembic schema differs."""
    migration_path = (
        Path(__file__).parents[1]
        / "alembic"
        / "versions"
        / "add_learner_concept_state.py"
    )
    spec = spec_from_file_location("learner_state_migration_under_test", migration_path)
    assert spec is not None and spec.loader is not None
    migration = module_from_spec(spec)
    spec.loader.exec_module(migration)
    created_tables: dict[str, tuple[object, ...]] = {}
    created_indexes: dict[str, tuple[str, tuple[str, ...]]] = {}

    monkeypatch.setattr(
        migration.op,
        "create_table",
        lambda name, *items, **_kwargs: created_tables.setdefault(name, items),
    )
    monkeypatch.setattr(
        migration.op,
        "create_index",
        lambda name, table, columns, **_kwargs: created_indexes.setdefault(
            name, (table, tuple(columns))
        ),
    )

    migration.upgrade()

    for table_name in (
        "learner_concept_states",
        "learner_state_profiles",
        "learner_observation_events",
    ):
        assert table_name in created_tables
        migration_columns = {
            item.name for item in created_tables[table_name] if hasattr(item, "type")
        }
        assert migration_columns == set(Base.metadata.tables[table_name].c.keys())

    expected_indexes = {
        index.name: (table.name, tuple(index.columns.keys()))
        for table_name in created_tables
        for table in (Base.metadata.tables[table_name],)
        for index in table.indexes
    }
    assert created_indexes == expected_indexes
