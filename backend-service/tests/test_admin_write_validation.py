"""Bad admin input is refused with a 4xx that names the problem, never a 500 or a silent save."""

import pytest

API = "/api/v1/admin"


@pytest.fixture
async def course_tree(async_client, admin_headers):
    async def post(path, body):
        response = await async_client.post(f"{API}/{path}", json=body, headers=admin_headers)
        assert response.status_code == 200, response.text
        return response.json()["data"]["id"]

    course = await post("courses", {"title": "C", "language": "en", "level": "A1"})
    unit = await post("units", {"course_id": course, "title": "U", "order_index": 0})
    lesson = await post(
        "lessons", {"unit_id": unit, "title": "L", "order_index": 0, "lesson_type": "lesson"}
    )
    return {"courses": course, "units": unit, "lessons": lesson}


@pytest.mark.parametrize(
    ("resource", "field"),
    [("courses", "title"), ("courses", "level"), ("units", "title"), ("lessons", "title"), ("lessons", "xp_reward")],
)
async def test_explicit_null_for_a_required_course_field_is_422(
    async_client, admin_headers, course_tree, resource, field
):
    response = await async_client.put(
        f"{API}/{resource}/{course_tree[resource]}", json={field: None}, headers=admin_headers
    )
    assert response.status_code == 422, response.text


@pytest.mark.parametrize("content", ["abc", {"exercises": "abc"}])
async def test_lesson_content_must_be_an_object_with_an_exercise_list(
    async_client, admin_headers, course_tree, content
):
    response = await async_client.put(
        f"{API}/lessons/{course_tree['lessons']}/content",
        json={"content": content},
        headers=admin_headers,
    )
    assert response.status_code == 422, response.text


@pytest.mark.parametrize(
    ("path", "body"),
    [
        ("grammar", {"title": "G", "content": "c", "level": "Z9"}),
        ("questions", {"prompt": "p", "difficulty_level": "Z9"}),
        ("questions", {"prompt": "p", "grammar_id": "11111111-1111-4111-8111-111111111111"}),
        ("test-exams", {"title": "E", "level": "Z9"}),
        ("test-exams", {"title": "E", "passing_score": 101}),
        ("shop", {"name": "N", "description": "d", "item_type": "hint_pack", "price_gems": -5}),
    ],
)
async def test_invalid_admin_create_is_4xx(async_client, admin_headers, path, body):
    response = await async_client.post(f"{API}/{path}", json=body, headers=admin_headers)
    assert response.status_code in (404, 422), response.text


async def test_null_grammar_title_is_422(async_client, admin_headers):
    created = await async_client.post(
        f"{API}/grammar", json={"title": "G", "content": "c"}, headers=admin_headers
    )
    response = await async_client.put(
        f"{API}/grammar/{created.json()['data']['id']}", json={"title": None}, headers=admin_headers
    )
    assert response.status_code == 422, response.text


@pytest.mark.parametrize("bad", [{"part_of_speech": "nounn"}, {"difficulty_level": "Z1"}])
async def test_unknown_vocabulary_enum_is_422(async_client, admin_headers, bad):
    response = await async_client.post(
        f"{API}/vocabulary",
        params={"word": "w", "definition": "d", "translation": "t", **bad},
        headers=admin_headers,
    )
    assert response.status_code == 422, response.text


async def test_duplicate_vocabulary_is_409(async_client, admin_headers):
    params = {"word": "twice", "definition": "d", "translation": "t"}
    first = await async_client.post(f"{API}/vocabulary", params=params, headers=admin_headers)
    second = await async_client.post(f"{API}/vocabulary", params=params, headers=admin_headers)
    assert (first.status_code, second.status_code) == (200, 409), second.text


@pytest.mark.parametrize(
    ("path", "header", "good", "bad"),
    [
        ("vocabulary", "word,definition,translation,part_of_speech,difficulty_level", "ok,d,t,noun,A1", "no,d,t,n.,Z9"),
        ("grammar", "title,level,content", "ok,A1,c", "no,Z9,c"),
        ("questions", "prompt,difficulty_level", "ok,A1", "no,Z9"),
        ("test-exams", "title,level", "ok,A1", "no,Z9"),
    ],
)
async def test_one_bad_import_row_is_reported_and_the_rest_are_saved(
    async_client, admin_headers, path, header, good, bad
):
    response = await async_client.post(
        f"{API}/{path}/bulk-import",
        files={"file": ("rows.csv", f"{header}\n{good}\n{bad}\n", "text/csv")},
        headers=admin_headers,
    )
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["created"] == 1
    assert len(data["errors"]) == 1 and data["errors"][0].startswith("Row 3")


ACHIEVEMENT = {"name": "A", "slug": "a", "description": "d", "condition_type": "lesson_complete"}


async def test_duplicate_achievement_is_409(async_client, admin_headers):
    first = await async_client.post(f"{API}/achievements", params=ACHIEVEMENT, headers=admin_headers)
    same_slug = await async_client.post(
        f"{API}/achievements", params={**ACHIEVEMENT, "name": "B"}, headers=admin_headers
    )
    other = await async_client.post(
        f"{API}/achievements", params={**ACHIEVEMENT, "name": "C", "slug": "c"}, headers=admin_headers
    )
    renamed = await async_client.put(
        f"{API}/achievements/{other.json()['data']['id']}", params={"name": "A"}, headers=admin_headers
    )
    assert (first.status_code, same_slug.status_code, renamed.status_code) == (200, 409, 409)


@pytest.mark.parametrize("bad", [{"rarity": "x" * 100}, {"gems_reward": -1}, {"xp_reward": -1}])
async def test_invalid_achievement_value_is_422(async_client, admin_headers, bad):
    response = await async_client.post(
        f"{API}/achievements", params={**ACHIEVEMENT, **bad}, headers=admin_headers
    )
    assert response.status_code == 422, response.text


async def test_shop_stock_can_be_set_back_to_unlimited(async_client, admin_headers):
    created = await async_client.post(
        f"{API}/shop",
        json={"name": "N", "description": "d", "item_type": "hint_pack", "price_gems": 5, "stock_quantity": 3},
        headers=admin_headers,
    )
    item_id = created.json()["data"]["id"]

    await async_client.put(f"{API}/shop/{item_id}", json={"stock_quantity": None}, headers=admin_headers)

    items = await async_client.get(f"{API}/shop?include_unavailable=true", headers=admin_headers)
    assert next(i for i in items.json()["data"] if i["id"] == item_id)["stock_quantity"] is None
