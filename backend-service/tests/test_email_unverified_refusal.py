"""A refused purchase must say why in a field the app can branch on."""

from app.core.security import create_access_token
from app.models.user import User


async def test_unverified_purchase_answers_403_with_a_reason(async_client, db_session, test_user):
    user = await db_session.get(User, test_user.id)
    user.is_verified = False
    await db_session.commit()
    headers = {"Authorization": f"Bearer {create_access_token(data={'sub': str(test_user.id)})}"}

    response = await async_client.post(
        "/api/v1/gamification/shop/purchase", json={"item_id": "streak_freeze", "quantity": 1}, headers=headers
    )

    assert response.status_code == 403
    assert response.json()["error"]["details"]["reason"] == "email_unverified"
