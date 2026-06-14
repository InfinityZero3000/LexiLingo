"""Stable errors used by the STT WebSocket protocol."""

from enum import Enum


class STTErrorCode(str, Enum):
    INVALID_START = "INVALID_START"
    UNSUPPORTED_AUDIO_FORMAT = "UNSUPPORTED_AUDIO_FORMAT"
    INVALID_FRAME = "INVALID_FRAME"
    SESSION_NOT_FOUND = "SESSION_NOT_FOUND"
    SESSION_EXPIRED = "SESSION_EXPIRED"
    SERVER_BUSY = "SERVER_BUSY"
    AUDIO_QUEUE_FULL = "AUDIO_QUEUE_FULL"
    MODEL_NOT_READY = "MODEL_NOT_READY"
    PRIMARY_STT_FAILED = "PRIMARY_STT_FAILED"
    VERIFIER_FAILED = "VERIFIER_FAILED"
    VERIFIER_TIMEOUT = "VERIFIER_TIMEOUT"
    TEMP_STORAGE_FAILED = "TEMP_STORAGE_FAILED"
    INTERNAL_ERROR = "INTERNAL_ERROR"


class STTProtocolError(Exception):
    def __init__(self, code: STTErrorCode, message: str):
        super().__init__(message)
        self.code = code
        self.message = message
