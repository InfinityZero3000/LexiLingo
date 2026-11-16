import pytest

ME = "/api/v1/users/me"


@pytest.mark.asyncio
async def test_defaults_to_the_app_language(async_client, auth_headers):
    body = (await async_client.get(ME, headers=auth_headers)).json()
    assert body["lexi_reply_language"] == "app"


@pytest.mark.asyncio
async def test_choice_is_saved_on_the_account(async_client, auth_headers):
    r = await async_client.put(ME, headers=auth_headers, json={"lexi_reply_language": "native"})
    assert r.status_code == 200, r.text
    assert r.json()["lexi_reply_language"] == "native"
    assert (await async_client.get(ME, headers=auth_headers)).json()["lexi_reply_language"] == "native"

    r = await async_client.put(ME, headers=auth_headers, json={"lexi_reply_language": "app"})
    assert r.json()["lexi_reply_language"] == "app"


@pytest.mark.asyncio
async def test_unrelated_update_keeps_the_choice(async_client, auth_headers):
    await async_client.put(ME, headers=auth_headers, json={"lexi_reply_language": "native"})
    r = await async_client.put(ME, headers=auth_headers, json={"display_name": "New Name"})
    assert r.json()["lexi_reply_language"] == "native"


@pytest.mark.asyncio
async def test_only_the_two_choices_are_accepted(async_client, auth_headers):
    r = await async_client.put(ME, headers=auth_headers, json={"lexi_reply_language": "fr"})
    assert r.status_code == 422
