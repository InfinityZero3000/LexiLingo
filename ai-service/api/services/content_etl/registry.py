"""Immutable allowlists for licensed ETL sources and source-specific licenses."""

from __future__ import annotations

from dataclasses import dataclass

from pydantic import AnyHttpUrl, TypeAdapter, ValidationError

from api.services.content_etl.contracts import AllowedLicenseId, SourceName


class SourceRegistryError(ValueError):
    """Raised when a source, URL, or license falls outside the allowlist."""


@dataclass(frozen=True)
class SourceDefinition:
    source_name: SourceName
    official_url: str
    allowed_hosts: tuple[str, ...]
    allowed_licenses: tuple[AllowedLicenseId, ...]
    attribution_text: str
    default_enabled: bool
    forbidden_path_markers: tuple[str, ...] = ()


SOURCE_REGISTRY: dict[SourceName, SourceDefinition] = {
    SourceName.OEWN: SourceDefinition(
        source_name=SourceName.OEWN,
        official_url="https://en-word.net/static/english-wordnet-2025.xml.gz",
        allowed_hosts=("en-word.net", "github.com"),
        allowed_licenses=(AllowedLicenseId.CC_BY_4_0,),
        attribution_text="Open English WordNet 2025",
        default_enabled=True,
    ),
    SourceName.CMUDICT: SourceDefinition(
        source_name=SourceName.CMUDICT,
        official_url="https://github.com/cmusphinx/cmudict",
        allowed_hosts=(
            "github.com",
            "raw.githubusercontent.com",
            "codeload.github.com",
        ),
        allowed_licenses=(AllowedLicenseId.CMUDICT,),
        attribution_text="Carnegie Mellon Pronouncing Dictionary",
        default_enabled=True,
    ),
    SourceName.CEFR_J: SourceDefinition(
        source_name=SourceName.CEFR_J,
        official_url="https://github.com/openlanguageprofiles/olp-en-cefrj",
        allowed_hosts=(
            "github.com",
            "raw.githubusercontent.com",
            "codeload.github.com",
        ),
        allowed_licenses=(AllowedLicenseId.CEFR_J_COMMERCIAL,),
        attribution_text=(
            "The CEFR-J Wordlist Version 1.5, compiled by Yukio Tono, "
            "Tokyo University of Foreign Studies"
        ),
        default_enabled=True,
        forbidden_path_markers=("octanove",),
    ),
    SourceName.WIKIDATA: SourceDefinition(
        source_name=SourceName.WIKIDATA,
        official_url="https://www.wikidata.org/wiki/Special:EntityData",
        allowed_hosts=("www.wikidata.org",),
        allowed_licenses=(AllowedLicenseId.CC0_1_0,),
        attribution_text="Wikidata contributors",
        default_enabled=True,
    ),
    SourceName.TATOEBA: SourceDefinition(
        source_name=SourceName.TATOEBA,
        official_url="https://tatoeba.org/en/downloads",
        allowed_hosts=("tatoeba.org", "downloads.tatoeba.org"),
        allowed_licenses=(
            AllowedLicenseId.CC0_1_0,
            AllowedLicenseId.CC_BY_2_0_FR,
        ),
        attribution_text="Tatoeba contributors; retain per-record attribution",
        default_enabled=False,
    ),
    SourceName.LIBRISPEECH: SourceDefinition(
        source_name=SourceName.LIBRISPEECH,
        official_url="https://www.openslr.org/12",
        allowed_hosts=("www.openslr.org", "openslr.org"),
        allowed_licenses=(AllowedLicenseId.CC_BY_4_0,),
        attribution_text="LibriSpeech ASR corpus",
        default_enabled=False,
    ),
    SourceName.COMMON_VOICE: SourceDefinition(
        source_name=SourceName.COMMON_VOICE,
        official_url=(
            "https://datacollective.mozillafoundation.org/organization/"
            "cmfh0j9o10006ns07jq45h7xk"
        ),
        allowed_hosts=("datacollective.mozillafoundation.org",),
        allowed_licenses=(AllowedLicenseId.CC0_1_0,),
        attribution_text="Mozilla Common Voice contributors",
        default_enabled=False,
    ),
    SourceName.ADMIN_UPLOAD: SourceDefinition(
        source_name=SourceName.ADMIN_UPLOAD,
        official_url="",
        allowed_hosts=(),
        allowed_licenses=(AllowedLicenseId.ADMIN_OWNED,),
        attribution_text="Administrator-owned or commercially licensed upload",
        default_enabled=True,
    ),
}

_HTTP_URL_ADAPTER = TypeAdapter(AnyHttpUrl)


def _coerce_source_name(source_name: SourceName | str) -> SourceName:
    try:
        return SourceName(source_name)
    except ValueError as exc:
        raise SourceRegistryError(f"Unsupported ETL source: {source_name}") from exc


def get_source_definition(source_name: SourceName | str) -> SourceDefinition:
    normalized = _coerce_source_name(source_name)
    return SOURCE_REGISTRY[normalized]


def list_source_definitions() -> tuple[SourceDefinition, ...]:
    return tuple(SOURCE_REGISTRY[source_name] for source_name in SourceName)


def validate_source_license(
    source_name: SourceName | str,
    license_id: AllowedLicenseId | str,
) -> AllowedLicenseId:
    definition = get_source_definition(source_name)
    try:
        normalized_license = AllowedLicenseId(license_id)
    except ValueError as exc:
        raise SourceRegistryError(f"Unsupported license: {license_id}") from exc
    if normalized_license not in definition.allowed_licenses:
        raise SourceRegistryError(
            f"License {normalized_license.value} is not approved for "
            f"{definition.source_name.value}"
        )
    return normalized_license


def validate_source_url(
    source_name: SourceName | str,
    url: str,
) -> AnyHttpUrl:
    definition = get_source_definition(source_name)
    if definition.source_name == SourceName.ADMIN_UPLOAD:
        raise SourceRegistryError("Admin uploads do not accept remote source URLs")
    try:
        parsed = _HTTP_URL_ADAPTER.validate_python(url)
    except ValidationError as exc:
        raise SourceRegistryError("Source URL is invalid") from exc
    if parsed.scheme != "https":
        raise SourceRegistryError("Source URL must use HTTPS")
    if parsed.username is not None or parsed.password is not None:
        raise SourceRegistryError("Source URL must not contain credentials")
    if parsed.query is not None or parsed.fragment is not None:
        raise SourceRegistryError(
            "Source URL must not contain a query string or fragment"
        )
    if parsed.host not in definition.allowed_hosts:
        raise SourceRegistryError(
            f"Host {parsed.host!r} is not approved for {definition.source_name.value}"
        )

    lowered_path = parsed.path.lower()
    for marker in definition.forbidden_path_markers:
        if marker in lowered_path:
            label = "Octanove" if marker == "octanove" else marker
            raise SourceRegistryError(
                f"{label} files are excluded by the source license policy"
            )
    return parsed
