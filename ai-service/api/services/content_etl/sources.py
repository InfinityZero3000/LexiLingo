"""Source-specific sync configuration and download-to-activation orchestration."""

from __future__ import annotations

import gzip
import shutil
from dataclasses import dataclass
from pathlib import Path

from api.core.config import Settings, get_settings
from api.services.content_etl.adapters.base import SourceAdapter
from api.services.content_etl.adapters.cefr_j import (
    ATTRIBUTION_TEXT as CEFR_J_ATTRIBUTION,
    CEFRJAdapter,
    LICENSE_URL as CEFR_J_LICENSE_URL,
)
from api.services.content_etl.adapters.cmudict import (
    ATTRIBUTION_TEXT as CMU_ATTRIBUTION,
    CMUDictAdapter,
    LICENSE_URL as CMU_LICENSE_URL,
)
from api.services.content_etl.adapters.oewn import (
    ATTRIBUTION_TEXT as OEWN_ATTRIBUTION,
    LICENSE_URL as OEWN_LICENSE_URL,
    OEWNAdapter,
)
from api.services.content_etl.contracts import AllowedLicenseId, SourceName
from api.services.content_etl.downloader import SecureDownloader
from api.services.content_etl.pipeline import ETLPipeline, PipelineReport
from api.services.content_etl.registry import get_source_definition
from api.services.content_etl.storage import SnapshotStorage


class SourceSyncConfigurationError(ValueError):
    """Raised when a source lacks an immutable, supported sync configuration."""


@dataclass(frozen=True)
class SourceSyncSpec:
    source_name: SourceName
    source_version: str
    download_url: str
    expected_sha256: str
    adapter: SourceAdapter
    license_id: AllowedLicenseId
    license_url: str
    attribution_text: str
    official_url: str


def build_source_sync_spec(
    source_name: SourceName | str,
    *,
    settings: Settings | None = None,
) -> SourceSyncSpec:
    source = SourceName(source_name)
    config = settings or get_settings()
    definition = get_source_definition(source)

    if source == SourceName.OEWN:
        version = _require_pin(
            "CONTENT_ETL_OEWN_VERSION",
            config.CONTENT_ETL_OEWN_VERSION,
        )
        return SourceSyncSpec(
            source_name=source,
            source_version=version,
            download_url=(
                f"https://en-word.net/static/english-wordnet-{version}.xml.gz"
            ),
            expected_sha256=_required_checksum(
                "CONTENT_ETL_OEWN_SHA256",
                getattr(config, "CONTENT_ETL_OEWN_SHA256", "")
            ),
            adapter=OEWNAdapter(),
            license_id=AllowedLicenseId.CC_BY_4_0,
            license_url=OEWN_LICENSE_URL,
            attribution_text=OEWN_ATTRIBUTION,
            official_url=definition.official_url,
        )

    if source == SourceName.CMUDICT:
        version = _require_commit("CONTENT_ETL_CMU_REF", config.CONTENT_ETL_CMU_REF)
        return SourceSyncSpec(
            source_name=source,
            source_version=version,
            download_url=(
                "https://raw.githubusercontent.com/cmusphinx/cmudict/"
                f"{version}/cmudict.dict"
            ),
            expected_sha256=_required_checksum(
                "CONTENT_ETL_CMU_SHA256",
                getattr(config, "CONTENT_ETL_CMU_SHA256", "")
            ),
            adapter=CMUDictAdapter(),
            license_id=AllowedLicenseId.CMUDICT,
            license_url=CMU_LICENSE_URL,
            attribution_text=CMU_ATTRIBUTION,
            official_url=definition.official_url,
        )

    if source == SourceName.CEFR_J:
        version = _require_commit(
            "CONTENT_ETL_CEFR_J_REF",
            config.CONTENT_ETL_CEFR_J_REF,
        )
        member = str(
            getattr(
                config,
                "CONTENT_ETL_CEFR_J_PATH",
                "cefrj-vocabulary-profile-1.5.csv",
            )
        ).strip()
        if not member or "/" in member or "\\" in member:
            raise SourceSyncConfigurationError(
                "CONTENT_ETL_CEFR_J_PATH must be a repository-root filename"
            )
        return SourceSyncSpec(
            source_name=source,
            source_version=version,
            download_url=(
                "https://raw.githubusercontent.com/openlanguageprofiles/"
                f"olp-en-cefrj/{version}/{member}"
            ),
            expected_sha256=_required_checksum(
                "CONTENT_ETL_CEFR_J_SHA256",
                getattr(config, "CONTENT_ETL_CEFR_J_SHA256", "")
            ),
            adapter=CEFRJAdapter(),
            license_id=AllowedLicenseId.CEFR_J_COMMERCIAL,
            license_url=CEFR_J_LICENSE_URL,
            attribution_text=CEFR_J_ATTRIBUTION,
            official_url=definition.official_url,
        )

    raise SourceSyncConfigurationError(
        f"Automated remote sync is not configured for {source.value}; "
        "use an operator-provided licensed artifact until a pinned source "
        "adapter is configured"
    )


async def sync_source(
    spec: SourceSyncSpec,
    *,
    downloader: SecureDownloader,
    storage: SnapshotStorage,
    dry_run: bool,
) -> PipelineReport:
    if dry_run:
        return PipelineReport(
            source_name=spec.source_name.value,
            source_version=spec.source_version,
            status="dry_run",
        )

    download = await downloader.download(
        source_name=spec.source_name,
        version=spec.source_version,
        url=spec.download_url,
        expected_sha256=spec.expected_sha256,
    )
    adapter_path, cleanup_path = _materialize_adapter_input(
        download.path,
        storage=storage,
    )
    try:
        records = spec.adapter.parse(adapter_path)
        pipeline = ETLPipeline(
            storage=storage,
            max_quarantine_ratio=get_settings().CONTENT_ETL_MAX_QUARANTINE_RATIO,
        )
        return pipeline.run(
            source_name=spec.source_name,
            source_version=spec.source_version,
            adapter_name=spec.adapter.source_name,
            adapter_version=spec.adapter.adapter_version,
            license_id=spec.license_id,
            license_url=spec.license_url,
            attribution_text=spec.attribution_text,
            raw_records=records,
            raw_bytes=download.path.read_bytes(),
            official_url=spec.official_url,
        )
    finally:
        if cleanup_path is not None:
            cleanup_path.unlink(missing_ok=True)


def _materialize_adapter_input(
    raw_path: Path,
    *,
    storage: SnapshotStorage,
) -> tuple[Path, Path | None]:
    if raw_path.name.endswith(".gz") and not raw_path.name.endswith(".tar.gz"):
        output_path = storage.create_temp_file()
        try:
            with gzip.open(raw_path, "rb") as source, output_path.open("wb") as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)
        except Exception:
            output_path.unlink(missing_ok=True)
            raise
        return output_path, output_path
    return raw_path, None


def _require_pin(name: str, value: str) -> str:
    normalized = value.strip()
    if not normalized or normalized.lower() in {
        "head",
        "latest",
        "main",
        "master",
        "stable",
        "trunk",
    }:
        raise SourceSyncConfigurationError(
            f"{name} must use a pinned immutable version"
        )
    return normalized


def _require_commit(name: str, value: str) -> str:
    normalized = _require_pin(name, value).lower()
    if len(normalized) != 40 or any(ch not in "0123456789abcdef" for ch in normalized):
        raise SourceSyncConfigurationError(
            f"{name} must use a pinned 40-character commit SHA"
        )
    return normalized


def _required_checksum(name: str, value: str) -> str:
    normalized = value.strip().lower()
    if not normalized:
        raise SourceSyncConfigurationError(
            f"{name} must use the expected lowercase SHA-256 checksum"
        )
    if len(normalized) != 64 or any(ch not in "0123456789abcdef" for ch in normalized):
        raise SourceSyncConfigurationError(
            f"{name} must be a lowercase SHA-256 value"
        )
    return normalized
