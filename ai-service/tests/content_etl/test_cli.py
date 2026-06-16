from __future__ import annotations

import hashlib
from pathlib import Path

import httpx
from typer.testing import CliRunner

from api.services.content_etl import cli
from api.services.content_etl.adapters.cefr_j import CEFRJAdapter
from api.services.content_etl.contracts import AllowedLicenseId, SourceName
from api.services.content_etl.downloader import SecureDownloader
from api.services.content_etl.sources import SourceSyncSpec, sync_source
from api.services.content_etl.storage import SnapshotStorage


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
