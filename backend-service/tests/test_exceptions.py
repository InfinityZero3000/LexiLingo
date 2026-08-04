import pytest
from unittest.mock import MagicMock, patch

from app.core.exceptions import unhandled_exception_handler


@pytest.mark.asyncio
async def test_unhandled_exception_hides_message_when_debug_off():
    request = MagicMock()
    request.state.request_id = "req-1"
    with patch("app.core.exceptions.settings.DEBUG", False):
        response = await unhandled_exception_handler(request, ValueError("secret detail"))
    assert response.status_code == 500
    body = response.body.decode()
    assert "secret detail" not in body
    assert '"type":"ValueError"' in body or '"type": "ValueError"' in body


@pytest.mark.asyncio
async def test_unhandled_exception_shows_message_when_debug_on():
    request = MagicMock()
    request.state.request_id = "req-1"
    with patch("app.core.exceptions.settings.DEBUG", True):
        response = await unhandled_exception_handler(request, ValueError("secret detail"))
    assert response.status_code == 500
    assert "secret detail" in response.body.decode()
