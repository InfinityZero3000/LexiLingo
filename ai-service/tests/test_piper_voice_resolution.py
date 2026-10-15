"""The Piper voice lives where Dockerfile.prod puts it, and one config drives
both TTS paths."""

import os

import pytest

from api.services.handlers.piper_handler import PiperConfig, PiperHandler


def test_handler_searches_the_location_the_image_ships(monkeypatch, tmp_path):
    voice = "en_US-lessac-medium"
    shipped = tmp_path / "opt" / "voice-models" / "piper"
    shipped.mkdir(parents=True)
    (shipped / f"{voice}.onnx").write_bytes(b"onnx")

    real_exists = os.path.exists

    def fake_exists(path: str) -> bool:
        # Stand in for /opt/voice-models without writing outside tmp_path.
        if str(path).startswith("/opt/voice-models/piper/"):
            return real_exists(str(shipped / os.path.basename(str(path))))
        return real_exists(path)

    monkeypatch.setattr("api.services.handlers.piper_handler.os.path.exists", fake_exists)

    handler = PiperHandler(PiperConfig(model_path="en_US-lessac-medium", voice=voice))
    locations = [
        f"/opt/voice-models/piper/{voice}.onnx",
        f"models/piper/{voice}.onnx",
    ]
    assert fake_exists(locations[0]), "the shipped path must be searched first"
    assert handler.config.voice == voice


@pytest.mark.asyncio
async def test_gateway_piper_defaults_follow_the_tts_settings(monkeypatch):
    """Prod sets only TTS_*; a second family of PIPER_* defaults pointed the
    gateway at en_US-lessac-low, which the image does not ship."""
    from api.core.config import settings
    from api.services import gateway_setup
    from api.services.handlers import piper_handler

    for name in ("PIPER_MODEL_PATH", "PIPER_VOICE", "PIPER_SAMPLE_RATE"):
        monkeypatch.delenv(name, raising=False)

    async def no_load(self):
        return True

    monkeypatch.setattr(piper_handler.PiperHandler, "load", no_load)

    registered = {}

    class StubGateway:
        def register(self, **kwargs):
            registered.update(kwargs)

    await gateway_setup._register_piper(StubGateway())
    handler = await registered["loader_fn"]()

    assert handler.config.voice == settings.TTS_VOICE
    assert handler.config.model_path == settings.TTS_MODEL_PATH
    assert handler.config.voice != "en_US-lessac-low"
