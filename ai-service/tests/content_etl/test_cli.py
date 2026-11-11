from __future__ import annotations

import asyncio
import hashlib
from pathlib import Path

import pytest

import httpx
from typer.testing import CliRunner

from api.services.content_etl import cli
from api.services.content_etl.adapters.cefr_j import CEFRJAdapter
from api.services.content_etl.contracts import AllowedLicenseId, SourceName
from api.services.content_etl.downloader import SecureDownloader
from api.services.content_etl.sources import SourceSyncSpec, sync_source
from api.services.content_etl.storage import SnapshotStorage, StorageIntegrityError


runner = CliRunner()


def _spec(url: str, *, expected_sha256: str = "a" * 64) -> SourceSyncSpec:
    return SourceSyncSpec(
        source_name=SourceName.CEFR_J,
        source_version="1" * 40,
        download_url=url,
        expected_sha256=expected_sha256,
        adapter=CEFRJAdapter(),
        license_id=AllowedLicenseId.CEFR_J_COMMERCIAL,
        license_url="https://github.com/openlanguageprofiles/olp-en-cefrj",
        attribution_text="The CEFR-J Wordlist Version 1.5",
        official_url="https://github.com/openlanguageprofiles/olp-en-cefrj",
    )


def test_sync_source_downloads_normalizes_and_activates(tmp_path):
    body = b"headword,CEFR\nhello,A1\njourney,B1\n"
    digest = hashlib.sha256(body).hexdigest()
    url = (
        "https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/"
        f"{'1' * 40}/cefrj-vocabulary-profile-1.5.csv"
    )
    storage = SnapshotStorage(tmp_path)
    downloader = SecureDownloader(
        storage=storage,
        timeout_seconds=1,
        max_download_bytes=1024,
        user_agent="LexiLingo-ETL-Test/1.0",
        resolver=lambda _host: ["93.184.216.34"],
        transport=httpx.MockTransport(
            lambda _request: httpx.Response(200, content=body)
        ),
    )

    report = __import__("asyncio").run(
        sync_source(
            _spec(url, expected_sha256=digest),
            downloader=downloader,
            storage=storage,
            dry_run=False,
        )
    )

    assert report.status == "approved"
    assert report.approved == 2
    assert report.activated is True
    active = storage.read_active("cefr_j")
    assert active["source_version"] == "1" * 40
    manifest = storage.read_manifest("cefr_j", "1" * 40)
    assert manifest.raw_sha256 == digest


def test_cli_sync_write_invokes_real_sync_and_returns_failure(monkeypatch, tmp_path):
    calls: list[tuple[str, bool]] = []

    async def fake_sync(spec, *, downloader, storage, dry_run):
        calls.append((spec.source_name.value, dry_run))
        from api.services.content_etl.pipeline import PipelineReport

        return PipelineReport(
            source_name=spec.source_name.value,
            source_version=spec.source_version,
            status="failed",
            errors=["adapter failed"],
        )

    monkeypatch.setattr(cli, "build_source_sync_spec", lambda _source: _spec(
        "https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/"
        f"{'1' * 40}/cefrj-vocabulary-profile-1.5.csv"
    ))
    monkeypatch.setattr(cli, "sync_source", fake_sync)
    monkeypatch.setattr(
        cli,
        "build_downloader",
        lambda storage: object(),
    )

    result = runner.invoke(
        cli.app,
        [
            "sync",
            "--sources",
            "cefr_j",
            "--write",
            "--storage-root",
            str(tmp_path),
        ],
    )

    assert result.exit_code == 1
    assert calls == [("cefr_j", False)]
    assert "adapter failed" in result.output


def test_cli_sync_dry_run_does_not_create_snapshot_files(monkeypatch, tmp_path):
    monkeypatch.setattr(cli, "build_source_sync_spec", lambda _source: _spec(
        "https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/"
        f"{'1' * 40}/cefrj-vocabulary-profile-1.5.csv"
    ))

    result = runner.invoke(
        cli.app,
        [
            "sync",
            "--sources",
            "cefr_j",
            "--storage-root",
            str(tmp_path),
        ],
    )

    assert result.exit_code == 0
    assert not (Path(tmp_path) / "raw" / "cefr_j").exists()
    assert not (Path(tmp_path) / "active" / "cefr_j.json").exists()


_BODY = b"headword,CEFR\nhello,A1\njourney,B1\n"


def _downloader(storage: SnapshotStorage, handler) -> SecureDownloader:
    return SecureDownloader(
        storage=storage,
        timeout_seconds=1,
        max_download_bytes=1024,
        user_agent="LexiLingo-ETL-Test/1.0",
        resolver=lambda _host: ["93.184.216.34"],
        transport=httpx.MockTransport(handler),
    )


def _synced(tmp_path):
    digest = hashlib.sha256(_BODY).hexdigest()
    url = (
        "https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/"
        f"{'1' * 40}/cefrj-vocabulary-profile-1.5.csv"
    )
    storage = SnapshotStorage(tmp_path)
    spec = _spec(url, expected_sha256=digest)
    downloader = _downloader(storage, lambda _r: httpx.Response(200, content=_BODY))
    first = asyncio.run(
        sync_source(spec, downloader=downloader, storage=storage, dry_run=False)
    )
    assert first.status == "approved"
    return storage, spec


def test_resync_of_approved_version_is_a_noop_that_stays_active(tmp_path):
    storage, spec = _synced(tmp_path)
    storage.root.joinpath("active", "cefr_j.json").unlink()

    def offline(_request):
        raise AssertionError("re-sync must not touch the network")

    report = asyncio.run(
        sync_source(
            spec,
            downloader=_downloader(storage, offline),
            storage=storage,
            dry_run=False,
        )
    )

    assert report.status == "approved"
    assert report.activated is True
    assert report.approved == 2
    assert storage.read_active("cefr_j")["source_version"] == "1" * 40


def test_resync_with_a_different_pinned_checksum_fails(tmp_path):
    storage, spec = _synced(tmp_path)
    repinned = SourceSyncSpec(**{**spec.__dict__, "expected_sha256": "b" * 64})

    report = asyncio.run(
        sync_source(
            repinned,
            downloader=_downloader(storage, lambda _r: httpx.Response(500)),
            storage=storage,
            dry_run=False,
        )
    )

    assert report.status == "failed"
    assert "bump the version" in report.errors[0]


def test_cli_validate_rejects_a_tampered_snapshot_and_uses_given_root(tmp_path):
    storage, spec = _synced(tmp_path)
    args = [
        "validate",
        "--source",
        "cefr_j",
        "--version",
        spec.source_version,
        "--storage-root",
        str(tmp_path),
    ]
    assert runner.invoke(cli.app, args).exit_code == 0

    records = tmp_path / "normalized" / "cefr_j" / spec.source_version / "records.jsonl"
    records.parent.chmod(0o755)
    records.chmod(0o644)
    records.write_bytes(records.read_bytes().replace(b"hello", b"hullo"))

    result = runner.invoke(cli.app, args)
    assert result.exit_code == 1
    assert "ERROR" in result.output


def _approved_storage(tmp_path):
    return _synced(tmp_path)


def test_repeated_reads_of_an_active_snapshot_verify_records_once(tmp_path, monkeypatch):
    storage, _spec = _approved_storage(tmp_path)
    monkeypatch.setattr(SnapshotStorage, "_verified_snapshots", set())
    calls = []
    original = SnapshotStorage._verify_normalized_output

    def counting(self, manifest, **kwargs):
        calls.append(1)
        return original(self, manifest, **kwargs)

    monkeypatch.setattr(SnapshotStorage, "_verify_normalized_output", counting)

    for _ in range(3):
        SnapshotStorage(tmp_path).read_active_manifest("cefr_j")

    assert len(calls) == 1


def test_cached_verification_is_dropped_when_the_records_file_changes(tmp_path, monkeypatch):
    storage, spec = _approved_storage(tmp_path)
    monkeypatch.setattr(SnapshotStorage, "_verified_snapshots", set())
    storage.read_active_manifest("cefr_j")

    records = tmp_path / "normalized" / "cefr_j" / spec.source_version / "records.jsonl"
    records.parent.chmod(0o755)
    records.chmod(0o644)
    records.write_bytes(records.read_bytes() + b"\n")

    with pytest.raises(StorageIntegrityError):
        storage.read_active_manifest("cefr_j")


def test_read_normalized_records_validates_the_records_once(tmp_path, monkeypatch):
    storage, spec = _approved_storage(tmp_path)
    calls = []
    original = SnapshotStorage._verify_normalized_output

    def counting(self, manifest, **kwargs):
        calls.append(1)
        return original(self, manifest, **kwargs)

    monkeypatch.setattr(SnapshotStorage, "_verify_normalized_output", counting)

    records = storage.read_normalized_records("cefr_j", spec.source_version)

    assert len(records) == 2
    assert len(calls) == 1


def test_a_newer_adapter_gets_its_own_snapshot_version():
    from types import SimpleNamespace

    from api.services.content_etl.sources import build_source_sync_spec

    settings = SimpleNamespace(
        CONTENT_ETL_OEWN_VERSION="2025",
        CONTENT_ETL_OEWN_SHA256="a" * 64,
        CONTENT_ETL_CMU_REF="1" * 40,
        CONTENT_ETL_CMU_SHA256="b" * 64,
        CONTENT_ETL_CEFR_J_REF="2" * 40,
        CONTENT_ETL_CEFR_J_SHA256="c" * 64,
    )

    oewn = build_source_sync_spec("oewn", settings=settings)
    cmudict = build_source_sync_spec("cmudict", settings=settings)
    cefr_j = build_source_sync_spec("cefr_j", settings=settings)

    assert oewn.source_version == "2025+a2"
    assert oewn.download_url.endswith("/english-wordnet-2025.xml.gz")
    assert cmudict.source_version == "1" * 40 + "+a2"
    assert f"/{'1' * 40}/cmudict.dict" in cmudict.download_url
    assert cefr_j.source_version == "2" * 40 + "+a2"
