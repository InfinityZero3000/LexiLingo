from types import SimpleNamespace

from api.services.stt.engines.faster_whisper import FasterWhisperVerifier


def test_verifier_drops_high_no_speech_segments():
    verifier = FasterWhisperVerifier("base.en", "cpu", "int8")
    verifier._model = SimpleNamespace(
        transcribe=lambda *args, **kwargs: (
            [
                SimpleNamespace(
                    text="You",
                    start=0.0,
                    end=1.0,
                    avg_logprob=-0.1,
                    no_speech_prob=0.95,
                )
            ],
            SimpleNamespace(language="en"),
        )
    )
    result = verifier._transcribe_path("unused.wav", "en", 0)
    assert result.text == ""
    assert result.confidence == 0.0
