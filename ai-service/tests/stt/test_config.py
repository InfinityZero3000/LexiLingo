import pytest
from pydantic import ValidationError

from api.services.stt.config import STTConfig
from api.services.stt.schemas import StartMessage


def test_default_config_is_realtime_safe(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path)).validate()
    assert config.verify_model == "base.en"
    assert config.hard_cap_segment_ms == 15000
    assert config.audio_queue_max_frames == 200


def test_config_rejects_invalid_caps(tmp_path):
    with pytest.raises(ValueError):
        STTConfig(
            temp_dir=str(tmp_path),
            max_segment_ms=16000,
            hard_cap_segment_ms=15000,
        ).validate()


def test_config_rejects_inverted_confidence(tmp_path):
    with pytest.raises(ValueError):
        STTConfig(
            temp_dir=str(tmp_path),
            confidence_accept=0.7,
            confidence_verify=0.8,
        ).validate()


def test_start_message_rejects_path_like_session_id():
    with pytest.raises(ValidationError):
        StartMessage(session_id="../escape")
