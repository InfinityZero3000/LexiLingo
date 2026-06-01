from io import BytesIO
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import numpy as np
import pytest
from fastapi import UploadFile

from api.core.auth import AuthenticatedUser
from api.routes.pronunciation import assess_pronunciation
from api.services.hubert_service import PronunciationResult


class FakeHuBERT:
    async def analyze_pronunciation(self, audio, sample_rate=16000, reference_text=None):
        return PronunciationResult(
            overall_score=88.0,
            phoneme_scores={"overall_confidence": 0.92},
            errors=[],
            duration_ms=25.0,
            transcription=reference_text,
        )


@pytest.mark.asyncio
async def test_assess_pronunciation_returns_hubert_result(monkeypatch):
    quota = SimpleNamespace(
        rpm_used=1,
        rpm_limit=60,
        rpd_used=1,
        rpd_limit=1000,
        tpm_used=500,
        tpm_limit=100000,
        tpd_used=500,
        tpd_limit=1000000,
    )
    monkeypatch.setattr(
        "api.routes.pronunciation.enforce_user_quota",
        AsyncMock(return_value=quota),
    )
    monkeypatch.setattr(
        "api.routes.pronunciation.emit_ai_audit_event",
        AsyncMock(return_value=None),
    )
    monkeypatch.setattr(
        "api.routes.pronunciation._decode_audio_file",
        lambda path: (np.zeros(16000, dtype=np.float32), 16000),
    )
    monkeypatch.setattr(
        "api.routes.pronunciation.get_hubert_service",
        AsyncMock(return_value=FakeHuBERT()),
    )

    request = MagicMock()
    request.headers = {}
    audio = UploadFile(filename="recording.wav", file=BytesIO(b"fake-wav"))
    user = AuthenticatedUser(user_id="user-1", claims={})

    result = await assess_pronunciation(
        request,
        audio=audio,
        target_text="hello",
        current_user=user,
    )

    assert result["success"] is True
    assert result["overall_score"] == 88.0
    assert result["transcription"] == "hello"
