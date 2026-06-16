from __future__ import annotations

import pytest

from api.services.content_etl.contracts import AllowedLicenseId, SourceName
from api.services.content_etl.registry import (
    SourceRegistryError,
    get_source_definition,
    list_source_definitions,
    validate_source_license,
    validate_source_url,
)


def test_registry_contains_only_approved_sources_and_licenses():
    assert {source.value for source in SourceName} == {
        "oewn",
        "cmudict",
        "cefr_j",
        "wikidata",
        "tatoeba",
        "librispeech",
        "common_voice",
        "admin_upload",
    }
    assert {license_id.value for license_id in AllowedLicenseId} == {
        "CC0-1.0",
        "CC-BY-2.0-FR",
        "CC-BY-4.0",
        "LicenseRef-CMUdict",
        "LicenseRef-CEFR-J-Commercial",
        "LicenseRef-Admin-Owned",
        "LicenseRef-Generated",
    }


def test_registry_requires_attribution_and_uses_https_official_urls():
    definitions = list_source_definitions()

    assert {definition.source_name for definition in definitions} == set(SourceName)
    for definition in definitions:
        assert definition.attribution_text.strip()
        if definition.source_name != SourceName.ADMIN_UPLOAD:
            assert definition.official_url.startswith("https://")
            assert definition.url_rules


def test_large_and_per_record_corpora_are_disabled_by_default():
    assert get_source_definition(SourceName.TATOEBA).default_enabled is False
    assert get_source_definition(SourceName.LIBRISPEECH).default_enabled is False
    assert get_source_definition(SourceName.COMMON_VOICE).default_enabled is False

    assert get_source_definition(SourceName.OEWN).default_enabled is True
    assert get_source_definition(SourceName.CMUDICT).default_enabled is True
    assert get_source_definition(SourceName.CEFR_J).default_enabled is True
    assert get_source_definition(SourceName.WIKIDATA).default_enabled is True


@pytest.mark.parametrize(
    ("source_name", "license_id"),
    [
        (SourceName.OEWN, AllowedLicenseId.CC_BY_4_0),
        (SourceName.CMUDICT, AllowedLicenseId.CMUDICT),
        (SourceName.CEFR_J, AllowedLicenseId.CEFR_J_COMMERCIAL),
        (SourceName.WIKIDATA, AllowedLicenseId.CC0_1_0),
        (SourceName.TATOEBA, AllowedLicenseId.CC0_1_0),
        (SourceName.TATOEBA, AllowedLicenseId.CC_BY_2_0_FR),
        (SourceName.LIBRISPEECH, AllowedLicenseId.CC_BY_4_0),
        (SourceName.COMMON_VOICE, AllowedLicenseId.CC0_1_0),
        (SourceName.ADMIN_UPLOAD, AllowedLicenseId.ADMIN_OWNED),
    ],
)
def test_source_specific_license_allowlist(source_name, license_id):
    assert validate_source_license(source_name, license_id) == license_id


@pytest.mark.parametrize(
    "license_id",
    [
        "CC-BY-SA-4.0",
        "CC-BY-NC-4.0",
        "CC-BY-NC-SA-4.0",
        "unknown",
        "",
    ],
)
def test_unknown_sharealike_and_noncommercial_licenses_fail_closed(license_id):
    with pytest.raises((ValueError, SourceRegistryError)):
        validate_source_license(SourceName.OEWN, license_id)


def test_source_url_requires_exact_official_https_host():
    assert (
        validate_source_url(
            SourceName.OEWN,
            "https://en-word.net/static/english-wordnet-2025.xml.gz",
        ).host
        == "en-word.net"
    )

    for url in (
        "http://en-word.net/static/english-wordnet-2025.xml.gz",
        "https://en-word.net.evil.example/english-wordnet.xml.gz",
        "https://evil.example/?next=https://en-word.net/file",
        "https://user:secret@en-word.net/static/file.gz",
        "https://en-word.net/static/file.gz?token=secret",
    ):
        with pytest.raises(SourceRegistryError):
            validate_source_url(SourceName.OEWN, url)


def test_cefr_j_rejects_sharealike_octanove_paths():
    with pytest.raises(SourceRegistryError, match="Octanove"):
        validate_source_url(
            SourceName.CEFR_J,
            "https://raw.githubusercontent.com/openlanguageprofiles/"
            "olp-en-cefrj/0123456789abcdef0123456789abcdef01234567/"
            "octanove-vocabulary-profile.csv",
        )


@pytest.mark.parametrize(
    ("source_name", "url"),
    [
        (
            SourceName.CMUDICT,
            "https://github.com/attacker/cmudict/archive/"
            "0123456789abcdef0123456789abcdef01234567.tar.gz",
        ),
        (
            SourceName.CEFR_J,
            "https://raw.githubusercontent.com/attacker/olp-en-cefrj/"
            "0123456789abcdef0123456789abcdef01234567/wordlist.csv",
        ),
        (
            SourceName.OEWN,
            "https://github.com/globalwordnet/other-project/releases/download/"
            "2025/file.xml.gz",
        ),
        (
            SourceName.WIKIDATA,
            "https://www.wikidata.org/wiki/Special:EntityData/%252e%252e/"
            "unexpected.json",
        ),
    ],
)
def test_source_url_rejects_same_host_source_substitution(source_name, url):
    with pytest.raises(SourceRegistryError):
        validate_source_url(source_name, url)
