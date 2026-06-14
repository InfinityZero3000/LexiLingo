from api.services.stt.schemas import PrimaryResult, VerificationResult


class FakePrimarySession:
    def __init__(self, text="hello world", confidence=0.9):
        self.text = text
        self.confidence = confidence
        self.closed = False

    async def push_audio(self, pcm16, start_ms, end_ms):
        return PrimaryResult(
            text=self.text,
            confidence=self.confidence,
            confidence_source="fake",
            language="en",
            source="fake-primary",
        )

    async def finalize(self, audio):
        return PrimaryResult(
            text=self.text,
            confidence=self.confidence,
            confidence_source="fake",
            language="en",
            source="fake-primary",
        )

    async def close(self):
        self.closed = True


class FakePrimary:
    def __init__(self, session=None, fail_load=False):
        self.session = session or FakePrimarySession()
        self.fail_load = fail_load
        self.loads = 0

    async def load(self):
        self.loads += 1
        if self.fail_load:
            raise RuntimeError("primary failed")

    async def create_session(self, language):
        return self.session

    async def close(self):
        return None


class FakeVerifier:
    def __init__(self, text="verified text", confidence=0.95, fail=False):
        self.text = text
        self.confidence = confidence
        self.fail = fail
        self.loads = 0

    async def load(self):
        self.loads += 1
        if self.fail:
            raise RuntimeError("verifier failed")

    async def verify(self, audio, language):
        if self.fail:
            raise RuntimeError("verifier failed")
        return VerificationResult(
            text=self.text,
            confidence=self.confidence,
            confidence_source="fake_verifier",
            language=language,
            source="faster-whisper",
        )

    async def close(self):
        return None
