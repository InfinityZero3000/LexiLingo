from __future__ import annotations

import hashlib

import httpx
import pytest

from api.services.content_etl.downloader import (
    DownloadSecurityError,
    SecureDownloader,
)
from api.services.content_etl.storage import SnapshotStorage


def PUBLIC_IPS(_host):
    return ["93.184.216.34"]


class _UnknownLengthStream(httpx.AsyncByteStream):
    async def __aiter__(self):
        yield b"012345"
        yield b"67890"


def _downloader(tmp_path, handler, **overrides) -> SecureDownloader:
    return SecureDownloader(
        storage=SnapshotStorage(tmp_path),
        timeout_seconds=1,
        max_download_bytes=overrides.pop("max_download_bytes", 1024),
        user_agent="LexiLingo-ETL-Test/1.0",
        resolver=overrides.pop("resolver", PUBLIC_IPS),
        transport=httpx.MockTransport(handler),
        **overrides,
    )


@pytest.mark.asyncio
async def test_download_streams_hashes_and_promotes_verified_content(tmp_path):
    body = b"licensed dataset"
    expected = hashlib.sha256(body).hexdigest()

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["user-agent"] == "LexiLingo-ETL-Test/1.0"
        return httpx.Response(
            200,
            headers={"content-length": str(len(body))},
            content=body,
        )

    result = await _downloader(tmp_path, handler).download(
        source_name="oewn",
        version="2025",
        url="https://en-word.net/static/english-wordnet-2025.xml.gz",
        expected_sha256=expected,
    )

    assert result.sha256 == expected
    assert result.byte_count == len(body)
    assert result.path.read_bytes() == body
    assert result.path.name == "english-wordnet-2025.xml.gz"
    assert list((tmp_path / "tmp").iterdir()) == []


@pytest.mark.asyncio
async def test_download_revalidates_redirect_hosts_and_cleans_temp_files(tmp_path):
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            302,
            headers={"location": "https://evil.example/payload.tar.gz"},
        )

    downloader = _downloader(tmp_path, handler)
    with pytest.raises(DownloadSecurityError, match="not approved"):
        await downloader.download(
            source_name="oewn",
            version="2025",
            url="https://en-word.net/static/english-wordnet-2025.xml.gz",
        )

    assert list((tmp_path / "tmp").iterdir()) == []


@pytest.mark.asyncio
async def test_download_follows_an_approved_redirect(tmp_path):
    body = b"redirected dataset"

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/static/start.xml.gz":
            return httpx.Response(
                302,
                headers={"location": "/static/final.xml.gz"},
            )
        return httpx.Response(200, content=body)

    result = await _downloader(tmp_path, handler).download(
        source_name="oewn",
        version="redirect",
        url="https://en-word.net/static/start.xml.gz",
    )

    assert result.path.name == "final.xml.gz"
    assert result.path.read_bytes() == body


@pytest.mark.asyncio
async def test_download_blocks_private_loopback_and_link_local_dns(tmp_path):
    def handler(_request: httpx.Request) -> httpx.Response:
        raise AssertionError("network must not be reached")

    for private_ip in ("127.0.0.1", "10.0.0.5", "169.254.1.2", "::1"):
        downloader = _downloader(
            tmp_path,
            handler,
            resolver=lambda _host, ip=private_ip: [ip],
        )
        with pytest.raises(DownloadSecurityError, match="non-public"):
            await downloader.download(
                source_name="oewn",
                version=f"2025-{private_ip.replace(':', '_')}",
                url="https://en-word.net/static/english-wordnet-2025.xml.gz",
            )


@pytest.mark.asyncio
async def test_download_enforces_declared_and_streamed_size_limits(tmp_path):
    def declared_too_large(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, headers={"content-length": "11"}, content=b"")

    with pytest.raises(DownloadSecurityError, match="Content-Length"):
        await _downloader(
            tmp_path,
            declared_too_large,
            max_download_bytes=10,
        ).download(
            source_name="oewn",
            version="declared-limit",
            url="https://en-word.net/static/file.gz",
        )

    def streamed_too_large(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, stream=_UnknownLengthStream())

    with pytest.raises(DownloadSecurityError, match="byte limit"):
        await _downloader(
            tmp_path,
            streamed_too_large,
            max_download_bytes=10,
        ).download(
            source_name="oewn",
            version="stream-limit",
            url="https://en-word.net/static/file.gz",
        )

    assert list((tmp_path / "tmp").iterdir()) == []


@pytest.mark.asyncio
async def test_checksum_mismatch_never_promotes_raw_file(tmp_path):
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"wrong bytes")

    with pytest.raises(DownloadSecurityError, match="checksum"):
        await _downloader(tmp_path, handler).download(
            source_name="oewn",
            version="bad-checksum",
            url="https://en-word.net/static/file.gz",
            expected_sha256="a" * 64,
        )

    assert not (tmp_path / "raw" / "oewn" / "bad-checksum").exists()
    assert list((tmp_path / "tmp").iterdir()) == []


@pytest.mark.asyncio
async def test_timeout_and_redirect_errors_fail_closed_without_temp_files(tmp_path):
    def timeout_handler(_request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("timed out")

    with pytest.raises(DownloadSecurityError, match="timed out"):
        await _downloader(tmp_path, timeout_handler).download(
            source_name="oewn",
            version="timeout",
            url="https://en-word.net/static/file.gz",
        )

    def missing_location(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(302)

    with pytest.raises(DownloadSecurityError, match="Location"):
        await _downloader(tmp_path, missing_location).download(
            source_name="oewn",
            version="missing-location",
            url="https://en-word.net/static/file.gz",
        )

    def malformed_length(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-length": "not-a-number"},
            stream=_UnknownLengthStream(),
        )

    with pytest.raises(DownloadSecurityError, match="Content-Length"):
        await _downloader(tmp_path, malformed_length).download(
            source_name="oewn",
            version="bad-length",
            url="https://en-word.net/static/file.gz",
        )

    assert list((tmp_path / "tmp").iterdir()) == []
