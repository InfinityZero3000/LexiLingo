"""Streaming HTTPS downloader with source allowlists and SSRF defenses."""

from __future__ import annotations

import asyncio
import hashlib
import ipaddress
import os
import socket
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote

import httpx

from api.services.content_etl.contracts import SHA256_PATTERN, SourceName
from api.services.content_etl.registry import (
    SourceRegistryError,
    validate_source_url,
)
from api.services.content_etl.storage import (
    SnapshotStorage,
    StorageIntegrityError,
)


class DownloadSecurityError(ValueError):
    """Raised when a remote artifact fails a security or integrity gate."""


@dataclass(frozen=True)
class DownloadResult:
    path: Path
    sha256: str
    byte_count: int
    final_url: str


Resolver = Callable[[str], Iterable[str]]


class SecureDownloader:
    def __init__(
        self,
        *,
        storage: SnapshotStorage,
        timeout_seconds: int,
        max_download_bytes: int,
        user_agent: str,
        resolver: Resolver | None = None,
        transport: httpx.AsyncBaseTransport | None = None,
        max_redirects: int = 3,
    ):
        if timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        if max_download_bytes <= 0:
            raise ValueError("max_download_bytes must be positive")
        if max_redirects < 0:
            raise ValueError("max_redirects cannot be negative")
        self.storage = storage
        self.timeout_seconds = timeout_seconds
        self.max_download_bytes = max_download_bytes
        self.user_agent = user_agent
        self.resolver = resolver or _resolve_host
        self.transport = transport
        self.max_redirects = max_redirects

    async def download(
        self,
        *,
        source_name: SourceName | str,
        version: str,
        url: str,
        expected_sha256: str | None = None,
    ) -> DownloadResult:
        source = SourceName(source_name)
        current_url = url
        temp_path: Path | None = None

        if expected_sha256 is not None and not _is_sha256(expected_sha256):
            raise DownloadSecurityError("Expected checksum is not a SHA-256 value")

        try:
            async with httpx.AsyncClient(
                transport=self.transport,
                timeout=self.timeout_seconds,
                follow_redirects=False,
                trust_env=False,
                headers={"User-Agent": self.user_agent},
            ) as client:
                for redirect_count in range(self.max_redirects + 1):
                    parsed = await self._validate_destination(source, current_url)
                    async with client.stream("GET", str(parsed)) as response:
                        if response.is_redirect:
                            if redirect_count >= self.max_redirects:
                                raise DownloadSecurityError(
                                    "Maximum redirect count exceeded"
                                )
                            location = response.headers.get("location")
                            if not location:
                                raise DownloadSecurityError(
                                    "Redirect response has no Location header"
                                )
                            current_url = str(response.url.join(location))
                            continue

                        try:
                            response.raise_for_status()
                        except httpx.HTTPStatusError as exc:
                            raise DownloadSecurityError(
                                f"Dataset download returned HTTP {response.status_code}"
                            ) from exc

                        self._validate_content_length(response)
                        filename = _filename_from_url(str(response.url))
                        temp_path = self.storage.create_temp_file()
                        digest = hashlib.sha256()
                        byte_count = 0

                        with temp_path.open("wb") as output:
                            async for chunk in response.aiter_bytes():
                                byte_count += len(chunk)
                                if byte_count > self.max_download_bytes:
                                    raise DownloadSecurityError(
                                        "Dataset download exceeded streaming byte limit"
                                    )
                                digest.update(chunk)
                                output.write(chunk)
                            output.flush()
                            os.fsync(output.fileno())

                        actual_sha256 = digest.hexdigest()
                        if (
                            expected_sha256 is not None
                            and actual_sha256 != expected_sha256.lower()
                        ):
                            raise DownloadSecurityError(
                                "Dataset checksum does not match the pinned checksum"
                            )

                        try:
                            promoted = self.storage.promote_raw(
                                temp_path,
                                source_name=source,
                                version=version,
                                filename=filename,
                                sha256=actual_sha256,
                            )
                        except StorageIntegrityError as exc:
                            raise DownloadSecurityError(str(exc)) from exc
                        temp_path = None
                        return DownloadResult(
                            path=promoted,
                            sha256=actual_sha256,
                            byte_count=byte_count,
                            final_url=str(response.url),
                        )
        except httpx.TimeoutException as exc:
            raise DownloadSecurityError("Dataset download timed out") from exc
        except httpx.HTTPError as exc:
            raise DownloadSecurityError("Dataset download failed") from exc
        finally:
            if temp_path is not None:
                temp_path.unlink(missing_ok=True)

        raise DownloadSecurityError("Dataset download did not return a file")

    async def _validate_destination(
        self,
        source_name: SourceName,
        url: str,
    ) -> httpx.URL:
        try:
            parsed = validate_source_url(source_name, url)
        except SourceRegistryError as exc:
            raise DownloadSecurityError(str(exc)) from exc

        addresses = await asyncio.to_thread(self.resolver, parsed.host)
        address_list = list(addresses)
        if not address_list:
            raise DownloadSecurityError("Source host did not resolve")
        for address in address_list:
            try:
                ip = ipaddress.ip_address(address)
            except ValueError as exc:
                raise DownloadSecurityError(
                    "Source host resolver returned an invalid IP address"
                ) from exc
            if not ip.is_global:
                raise DownloadSecurityError(
                    f"Source host resolved to non-public address {address}"
                )
        return httpx.URL(str(parsed))

    def _validate_content_length(self, response: httpx.Response) -> None:
        raw_length = response.headers.get("content-length")
        if raw_length is None:
            return
        try:
            content_length = int(raw_length)
        except ValueError as exc:
            raise DownloadSecurityError("Invalid Content-Length header") from exc
        if content_length < 0 or content_length > self.max_download_bytes:
            raise DownloadSecurityError(
                "Content-Length exceeds the configured download limit"
            )


def _resolve_host(host: str) -> list[str]:
    return sorted(
        {
            item[4][0]
            for item in socket.getaddrinfo(
                host,
                443,
                type=socket.SOCK_STREAM,
            )
        }
    )


def _filename_from_url(url: str) -> str:
    filename = Path(unquote(httpx.URL(url).path)).name
    if not filename or filename in {".", ".."}:
        raise DownloadSecurityError("Dataset URL has no safe filename")
    return filename


def _is_sha256(value: str) -> bool:
    import re

    return re.fullmatch(SHA256_PATTERN, value.lower()) is not None
