"""TRACE-CAG learner-state load profile with per-user isolation checks."""

from __future__ import annotations

import json
import random
import stat
import threading
import uuid
from pathlib import Path

from locust import HttpUser, between, events, task


REPEATED_TOPICS = [
    "Explain past simple with one example",
    "Correct: I go to school yesterday",
    "Help me practice present perfect",
]
_CANARIES: set[str] = set()
_CANARY_LOCK = threading.Lock()
_IDENTITIES: list[tuple[str, str]] = []
_IDENTITY_INDEX = 0
_IDENTITY_LOCK = threading.Lock()
_INITIALIZATIONS_STARTED = 0
_INITIALIZATIONS_COMPLETED = 0
_INITIALIZATION_LOCK = threading.Lock()
REQUEST_TIMEOUT_SECONDS = 60


def _load_identities(path: str) -> list[tuple[str, str]]:
    mode = stat.S_IMODE(Path(path).stat().st_mode)
    if mode & 0o077:
        raise PermissionError("identity file must not be accessible by group/other")
    identities = []
    seen_tokens: set[str] = set()
    seen_user_ids: set[str] = set()
    with Path(path).open(encoding="utf-8") as source:
        for line_number, line in enumerate(source, start=1):
            if not line.strip():
                continue
            record = json.loads(line)
            token = str(record.get("token", "")).strip()
            user_id = str(record.get("user_id", "")).strip()
            if not token or not user_id:
                raise ValueError(
                    f"identity line {line_number} requires token and user_id"
                )
            if user_id in seen_user_ids:
                raise ValueError(f"duplicate user_id on identity line {line_number}")
            if token in seen_tokens:
                raise ValueError(f"duplicate token on identity line {line_number}")
            seen_user_ids.add(user_id)
            seen_tokens.add(token)
            identities.append((token, user_id))
    if not identities:
        raise ValueError("identity pool is empty")
    return identities


class TraceCAGLearnerUser(HttpUser):
    wait_time = between(0.2, 1.0)

    def on_start(self):
        global _IDENTITY_INDEX, _INITIALIZATIONS_STARTED, _INITIALIZATIONS_COMPLETED
        with _INITIALIZATION_LOCK:
            _INITIALIZATIONS_STARTED += 1
        if _IDENTITIES:
            with _IDENTITY_LOCK:
                self.token, self.user_id = _IDENTITIES[_IDENTITY_INDEX % len(_IDENTITIES)]
                _IDENTITY_INDEX += 1
        else:
            self.token = self.environment.parsed_options.token
            self.user_id = self.environment.parsed_options.user_id
        if not self.token or not self.user_id:
            raise RuntimeError("provide --tokens-file, or both --token and --user-id")
        response = self.client.post(
            "/api/v1/chat/sessions",
            json={"user_id": self.user_id, "title": "TRACE-CAG load validation"},
            headers={"Authorization": f"Bearer {self.token}"},
            name="chat:create-session",
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        if response.status_code >= 400:
            raise RuntimeError(f"session creation failed: HTTP {response.status_code}")
        self.session_id = response.json()["session_id"]
        self.canary = f"LX{uuid.uuid4().hex[:12]}"
        with _CANARY_LOCK:
            _CANARIES.add(self.canary)
        # Put the marker in this user's session history, then make every user
        # ask the same repeated query. A cache key that omits user/session state
        # can now return a response influenced by another learner's marker.
        seed_ok = self._chat(f"Remember my private exercise code: {self.canary}", "seed")
        isolation_ok = self._chat(
            "What is my private exercise code? Reply with only the code.",
            "isolation",
            require_own_canary=True,
        )
        if not seed_ok or not isolation_ok:
            raise RuntimeError("learner isolation initialization failed")
        with _INITIALIZATION_LOCK:
            _INITIALIZATIONS_COMPLETED += 1

    def _chat(
        self, message: str, scenario: str, *, require_own_canary: bool = False
    ):
        with self.client.post(
            "/api/v1/chat/messages",
            json={
                "user_id": self.user_id,
                "session_id": self.session_id,
                "message": message,
            },
            headers={"Authorization": f"Bearer {self.token}"},
            name=f"chat:{scenario}",
            catch_response=True,
            timeout=REQUEST_TIMEOUT_SECONDS,
        ) as response:
            if response.status_code >= 400:
                response.failure(f"HTTP {response.status_code}")
                return False
            payload = response.json()
            serialized = response.text
            # Raw identifiers must never leak through cache/telemetry payloads.
            if any(marker in serialized for marker in ("learner_concept_states", "profile_snapshot")):
                response.failure("personalized internal state leaked")
                return False
            with _CANARY_LOCK:
                foreign_canaries = _CANARIES - {self.canary}
            leaked = next((item for item in foreign_canaries if item in serialized), None)
            if leaked:
                response.failure("cross-user canary leaked through personalized cache")
            if require_own_canary and self.canary not in serialized:
                response.failure("own learner canary missing from isolation response")
                return False
            metadata = payload.get("metadata", {})
            events.request.fire(
                request_type="METRIC",
                name=f"degraded:{bool(metadata.get('observation_durability_degraded'))}",
                response_time=0,
                response_length=0,
            )
            return not leaked

    @task(70)
    def repeated_topic(self):
        prompt = random.choice(REPEATED_TOPICS)
        self._chat(prompt, "repeated")

    @task(20)
    def new_topic(self):
        self._chat(f"Teach me topic {uuid.uuid4().hex[:8]}", "new")

    @task(10)
    def incorrect_burst(self):
        self._chat("Yesterday she go market and buy two apple", "incorrect")


@events.init_command_line_parser.add_listener
def add_token_argument(parser):
    parser.add_argument("--token", env_var="LEXILINGO_LOAD_TOKEN", default="")
    parser.add_argument("--user-id", env_var="LEXILINGO_LOAD_USER_ID", default="")
    parser.add_argument(
        "--tokens-file", env_var="LEXILINGO_LOAD_TOKENS_FILE", default=""
    )


@events.test_start.add_listener
def load_identity_pool(environment, **_kwargs):
    global _IDENTITIES, _IDENTITY_INDEX
    global _INITIALIZATIONS_STARTED, _INITIALIZATIONS_COMPLETED
    path = environment.parsed_options.tokens_file
    _IDENTITIES = _load_identities(path) if path else []
    _IDENTITY_INDEX = 0
    _INITIALIZATIONS_STARTED = 0
    _INITIALIZATIONS_COMPLETED = 0
    expected_users = int(environment.parsed_options.num_users or 0)
    if _IDENTITIES and expected_users > len(_IDENTITIES):
        raise RuntimeError(
            f"identity pool has {len(_IDENTITIES)} entries for {expected_users} users"
        )
    if not _IDENTITIES and expected_users > 1:
        raise RuntimeError("multiple users require a unique identity pool via --tokens-file")


@events.test_stop.add_listener
def require_completed_isolation(environment, **_kwargs):
    with _INITIALIZATION_LOCK:
        incomplete = _INITIALIZATIONS_STARTED - _INITIALIZATIONS_COMPLETED
    if incomplete:
        environment.process_exit_code = 1
        environment.runner.stats.log_error(
            "LOAD",
            "learner-isolation-incomplete",
            RuntimeError(f"{incomplete} user initialization(s) did not complete"),
        )
