"""Publish gate on IELTS passage provenance, and parity of the licence list with ai-service."""

import copy
import importlib.util
import re
from pathlib import Path

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.content_licenses import AI_SERVICE_LICENSE_IDS, ALLOWED_LICENSE_IDS
from app.models.ielts import IeltsTest

BACKEND = Path(__file__).resolve().parents[1]


def _paper() -> dict:
    spec = importlib.util.spec_from_file_location(
        "ielts_paper_academic_1", BACKEND / "scripts" / "ielts_paper_academic_1.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    content = copy.deepcopy(module.CONTENT)
    for section in content["sections"]:
        if section["skill"] == "listening":
            for part in section["parts"]:
                part["audio_url"] = "/media/ielts/part.mp3"
    return content


def _entries(**overrides) -> dict:
    base = {
        "license_id": "LicenseRef-Generated",
    }
    base.update(overrides)
    return {
        "passages": [
            {"section": f"reading:{n}", "title": f"p{n}", **base} for n in (1, 2, 3)
        ]
    }


async def _make(db: AsyncSession, provenance, published=False) -> IeltsTest:
    test = IeltsTest(
        title="T",
        test_type="academic",
        skill_scope="full",
        content=_paper(),
        provenance=provenance,
        is_published=published,
    )
    db.add(test)
    await db.commit()
    await db.refresh(test)
    return test


async def _publish(client: AsyncClient, headers: dict, test: IeltsTest, **extra):
    body = {"title": test.title, "is_published": True, **extra}
    return await client.put(f"/api/v1/admin/ielts/tests/{test.id}", json=body, headers=headers)


async def test_publish_refused_without_provenance(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    test = await _make(db_session, None)
    response = await _publish(async_client, admin_headers, test)
    assert response.status_code == 422
    assert "The Return of the Urban Beehive" in response.text
    await db_session.refresh(test)
    assert test.is_published is False


async def test_publish_refused_for_unknown_licence(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    test = await _make(db_session, _entries(license_id="All-Rights-Reserved"))
    response = await _publish(async_client, admin_headers, test)
    assert response.status_code == 422
    assert "license_id" in response.text


async def test_publish_refused_for_cc_by_sa_without_attribution(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    test = await _make(
        db_session, _entries(license_id="CC-BY-SA-4.0", source_url="https://en.wikipedia.org/wiki/Bee")
    )
    response = await _publish(async_client, admin_headers, test)
    assert response.status_code == 422
    assert "attribution" in response.text


async def test_publish_refused_for_cc_by_sa_without_source_url(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    test = await _make(db_session, _entries(license_id="CC-BY-SA-4.0", attribution="Wikipedia"))
    response = await _publish(async_client, admin_headers, test)
    assert response.status_code == 422
    assert "source_url" in response.text


async def test_publish_allowed_with_valid_provenance(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    test = await _make(
        db_session,
        _entries(
            license_id="CC-BY-SA-4.0",
            attribution="Wikipedia contributors",
            source_url="https://en.wikipedia.org/wiki/Bee",
        ),
    )
    response = await _publish(async_client, admin_headers, test)
    assert response.status_code == 200, response.text
    assert response.json()["data"]["is_published"] is True
    assert response.json()["data"]["provenance"]["passages"][0]["license_id"] == "CC-BY-SA-4.0"


async def test_provenance_can_arrive_in_the_publish_request(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    test = await _make(db_session, None)
    response = await _publish(async_client, admin_headers, test, provenance=_entries())
    assert response.status_code == 200, response.text


async def test_published_test_is_not_retroactively_unpublished(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    test = await _make(db_session, None, published=True)
    response = await async_client.put(
        f"/api/v1/admin/ielts/tests/{test.id}",
        json={"title": "Renamed", "is_published": True},
        headers=admin_headers,
    )
    assert response.status_code == 200, response.text
    assert response.json()["data"]["is_published"] is True
    assert response.json()["data"]["provenance"] is None


def test_license_list_matches_ai_service():
    source = (
        BACKEND.parent / "ai-service" / "api" / "services" / "content_etl" / "contracts.py"
    ).read_text()
    block = re.search(r"class AllowedLicenseId\(str, Enum\):\n((?:    .+\n)+)", source).group(1)
    ai_ids = set(re.findall(r'= "([^"]+)"', block))
    assert ai_ids == set(AI_SERVICE_LICENSE_IDS)
    assert AI_SERVICE_LICENSE_IDS <= ALLOWED_LICENSE_IDS


async def test_learner_paper_carries_each_passages_attribution(
    async_client: AsyncClient, auth_headers: dict, db_session: AsyncSession
):
    entries = _entries(
        license_id="CC-BY-SA-4.0",
        attribution="From Wikipedia article 'Bee' (rev 1), CC BY-SA 4.0",
        source_url="https://en.wikipedia.org/wiki/Bee",
        adapted=True,
    )
    entries["passages"][1].update(license_id="LicenseRef-Public-Domain", adapted=False)
    test = await _make(db_session, entries, published=True)
    for path, method in ((f"/api/v1/ielts/tests/{test.id}", "get"), (f"/api/v1/ielts/tests/{test.id}/start", "post")):
        kwargs = {"json": {}} if method == "post" else {}
        response = await getattr(async_client, method)(path, headers=auth_headers, **kwargs)
        assert response.status_code == 200, response.text
        reading = next(s for s in response.json()["data"]["content"]["sections"] if s["skill"] == "reading")
        first, second = reading["parts"][0], reading["parts"][1]
        assert first["license_id"] == "CC-BY-SA-4.0"
        assert first["license_url"] == "https://creativecommons.org/licenses/by-sa/4.0/"
        assert first["attribution"].startswith("From Wikipedia")
        assert first["source_url"] == "https://en.wikipedia.org/wiki/Bee"
        assert first["adapted"] is True
        assert second["license_url"] is None and second["adapted"] is False


async def test_learner_paper_without_provenance_gains_no_fields(
    async_client: AsyncClient, auth_headers: dict, db_session: AsyncSession
):
    test = await _make(db_session, None, published=True)
    response = await async_client.get(f"/api/v1/ielts/tests/{test.id}", headers=auth_headers)
    reading = next(s for s in response.json()["data"]["content"]["sections"] if s["skill"] == "reading")
    assert all("license_id" not in p and "attribution" not in p for p in reading["parts"])


def test_license_url_is_derived_in_one_place():
    from app.core.content_licenses import license_url

    assert license_url("CC-BY-SA-3.0") == "https://creativecommons.org/licenses/by-sa/3.0/"
    assert license_url("LicenseRef-US-Gov-Public-Domain") is None
    assert license_url(None) is None
