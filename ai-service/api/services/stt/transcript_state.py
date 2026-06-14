"""Validated transcript state transitions."""


class TranscriptState:
    def __init__(self):
        self.partial = None
        self.candidates = {}
        self.finals = {}
        self.responses = {}

    def set_partial(self, event) -> None:
        self.partial = event

    def add_candidate(self, event) -> None:
        self.candidates[event.utterance_id] = event

    def add_final(self, event) -> None:
        self.candidates.pop(event.utterance_id, None)
        self.finals[event.utterance_id] = event
        self.partial = None

    def add_response(self, event: dict) -> None:
        utterance_id = event.get("utterance_id")
        if utterance_id:
            self.responses[utterance_id] = event
