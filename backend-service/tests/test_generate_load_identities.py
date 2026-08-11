import json
import stat
from argparse import Namespace
from uuid import UUID

import pytest

from scripts import generate_load_identities as generator


@pytest.mark.parametrize(
    "database_url",
    [
        None,
        "postgresql+asyncpg://user:pass@localhost/lexilingo",
        "postgresql+asyncpg://user:pass@localhost/lexilingo_testing",
    ],
)
def test_database_guard_requires_explicit_test_database(monkeypatch, database_url):
    if database_url is None:
        monkeypatch.delenv("DATABASE_URL", raising=False)
    else:
        monkeypatch.setenv("DATABASE_URL", database_url)

    with pytest.raises(RuntimeError):
        generator._require_test_database()


def test_database_guard_accepts_test_suffix(monkeypatch):
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql+asyncpg://user:pass@localhost/lexilingo_load_test",
    )

    generator._require_test_database()


@pytest.mark.parametrize("count", [0, -1, 10_001])
def test_main_rejects_count_outside_bounds(monkeypatch, tmp_path, count):
    monkeypatch.setattr(
        generator,
        "_parse_args",
        lambda: Namespace(count=count, output=tmp_path / "identities.jsonl"),
    )

    with pytest.raises(ValueError, match="between 1 and 10000"):
        generator.main()


def test_main_writes_unique_seeded_identities_with_private_permissions(
    monkeypatch, tmp_path, capsys
):
    output = tmp_path / "private" / "identities.jsonl"
    ids = [
        UUID("11111111-1111-1111-1111-111111111111"),
        UUID("22222222-2222-2222-2222-222222222222"),
        UUID("33333333-3333-3333-3333-333333333333"),
    ]
    generated = iter(ids)
    seeded = []

    async def seed_users(user_ids):
        seeded.extend(user_ids)

    monkeypatch.setattr(
        generator,
        "_parse_args",
        lambda: Namespace(count=3, output=output),
    )
    monkeypatch.setattr(generator, "_require_test_database", lambda: None)
    monkeypatch.setattr(generator.uuid, "uuid4", lambda: next(generated))
    monkeypatch.setattr(generator, "_seed_users", seed_users)
    monkeypatch.setattr(
        generator,
        "create_access_token",
        lambda claims: f"private-token-{claims['sub']}",
    )

    assert generator.main() == 0

    records = [json.loads(line) for line in output.read_text().splitlines()]
    assert seeded == ids
    assert {record["user_id"] for record in records} == {str(item) for item in ids}
    assert len({record["token"] for record in records}) == 3
    assert stat.S_IMODE(output.stat().st_mode) == 0o600
    stdout = capsys.readouterr().out
    assert "private-token" not in stdout
    assert "seeded 3 load identities" in stdout
