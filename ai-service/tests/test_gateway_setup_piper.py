import pytest

from api.services import gateway_setup
from api.services.handlers.piper_handler import PiperHandler


@pytest.mark.asyncio
async def test_piper_registration_uses_configured_sample_rate(monkeypatch):
    registered = {}

    class Gateway:
        def register(self, **kwargs):
            registered.update(kwargs)

    async def load(_self):
        return True

    monkeypatch.setenv("PIPER_SAMPLE_RATE", "24000")
    monkeypatch.setattr(PiperHandler, "load", load)

    await gateway_setup._register_piper(Gateway())
    handler = await registered["loader_fn"]()

    assert handler.config.sample_rate == 24000
