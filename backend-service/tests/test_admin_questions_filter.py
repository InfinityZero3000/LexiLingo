import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import QuestionItem

URL = "/api/v1/admin/questions"


@pytest.fixture
async def seeded(db_session: AsyncSession) -> None:
    rows = [
        ("Choose the correct Verb form", "A1", "mcq"),
        ("Pick the right preposition", "B1", "mcq"),
        ("Fill the blank with a VERB", "B1", "fill_blank"),
        ("Order the words", "C1", "ordering"),
    ]
    for prompt, level, qtype in rows:
        db_session.add(QuestionItem(prompt=prompt, difficulty_level=level, question_type=qtype))
    await db_session.commit()


async def _prompts(client: AsyncClient, headers: dict, **params: str) -> set[str]:
    response = await client.get(URL, headers=headers, params=params)
    assert response.status_code == 200
    return {item["prompt"] for item in response.json()["data"]}


@pytest.mark.asyncio
async def test_no_filter_returns_all(async_client: AsyncClient, admin_headers: dict, seeded: None):
    assert len(await _prompts(async_client, admin_headers)) == 4


@pytest.mark.asyncio
async def test_level_is_case_insensitive_exact(async_client: AsyncClient, admin_headers: dict, seeded: None):
    assert await _prompts(async_client, admin_headers, level="b1") == {
        "Pick the right preposition",
        "Fill the blank with a VERB",
    }


@pytest.mark.asyncio
async def test_q_substring_is_case_insensitive(async_client: AsyncClient, admin_headers: dict, seeded: None):
    assert await _prompts(async_client, admin_headers, q="  verb ") == {
        "Choose the correct Verb form",
        "Fill the blank with a VERB",
    }


@pytest.mark.asyncio
async def test_filters_intersect(async_client: AsyncClient, admin_headers: dict, seeded: None):
    assert await _prompts(async_client, admin_headers, level="B1", q="verb") == {"Fill the blank with a VERB"}
    assert await _prompts(async_client, admin_headers, level="C1", q="verb") == set()


@pytest.mark.asyncio
async def test_question_type_filter(async_client: AsyncClient, admin_headers: dict, seeded: None):
    assert await _prompts(async_client, admin_headers, question_type="ordering") == {"Order the words"}
    assert len(await _prompts(async_client, admin_headers, question_type="mcq", level="B1")) == 1


@pytest.mark.asyncio
async def test_blank_params_are_ignored(async_client: AsyncClient, admin_headers: dict, seeded: None):
    assert len(await _prompts(async_client, admin_headers, level="", q="  ")) == 4


@pytest.mark.asyncio
async def test_q_over_200_chars_is_rejected(async_client: AsyncClient, admin_headers: dict):
    response = await async_client.get(URL, headers=admin_headers, params={"q": "x" * 201})
    assert response.status_code == 422
