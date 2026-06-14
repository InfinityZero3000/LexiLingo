"""Policy for selective Faster-Whisper verification."""

from dataclasses import dataclass

from api.services.stt.config import STTConfig
from api.services.stt.schemas import PrimaryResult, UseCase


@dataclass(frozen=True)
class VerifyDecision:
    verify: bool
    reason: str


class VerifierRouter:
    def __init__(self, config: STTConfig):
        self.config = config

    def decide(
        self, result: PrimaryResult, duration_ms: int, use_case: UseCase
    ) -> VerifyDecision:
        text = result.text.strip()
        if duration_ms < 500:
            return VerifyDecision(False, "very_short")
        if result.confidence < self.config.confidence_verify:
            return VerifyDecision(True, "low_confidence")
        if use_case != UseCase.CONVERSATION:
            return VerifyDecision(True, "accuracy_sensitive_use_case")
        suspicious = (
            not text or _has_repetition(text) or any(char.isdigit() for char in text)
        )
        if result.confidence < self.config.confidence_accept and suspicious:
            return VerifyDecision(True, "borderline_suspicious")
        return VerifyDecision(False, "accepted_primary")


def _has_repetition(text: str) -> bool:
    words = [word.lower() for word in text.split()]
    return any(
        words[index : index + 3] == words[index + 3 : index + 6]
        for index in range(max(0, len(words) - 5))
    )
