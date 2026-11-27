"""The exact body the Flutter app PUTs to the reminder preferences must be accepted."""

APP_BODY = {
    "enabled": True,
    "push_enabled": True,
    "email_enabled": False,
    "reminder_time_local": "08:30",
    "timezone": "Asia/Ho_Chi_Minh",
    "min_due_count": 5,
    "email_cadence_days": 3,
    "nurture_emails_enabled": True,
}


async def test_the_app_payload_is_accepted(async_client, auth_headers):
    response = await async_client.put("/api/v1/users/me/reminder-preferences", json=APP_BODY, headers=auth_headers)

    assert response.status_code == 200, response.text
    assert response.json()["data"]["reminder_time_local"] == "08:30"
