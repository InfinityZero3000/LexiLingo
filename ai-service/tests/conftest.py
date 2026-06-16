"""
Pytest Fixtures for AI Service Tests

Provides shared fixtures for testing trace_cag nodes,
services, and integrations.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from typing import Dict, Any


# ============================================================
# MOCK FIXTURES
# ============================================================


@pytest.fixture
def mock_model_gateway():
    """Mock ModelGateway for isolated node testing."""
    gateway = AsyncMock()
    gateway.execute_task = AsyncMock(return_value={
        "success": True,
        "data": {
            "text": "Great job! Your sentence is well-formed.",
            "errors": [],
        },
        "latency_ms": 50,
    })
    return gateway


@pytest.fixture
def mock_kg_service():
    """Mock Knowledge Graph service."""
    kg = MagicMock()
    kg.expand_concepts = MagicMock(return_value=[
        {
            "concept_id": "past_tense",
            "title": "Past Tense",
            "category": "grammar",
            "level": 1,
            "examples": ["I walked to school", "She played piano"],
        },
        {
            "concept_id": "regular_verbs",
            "title": "Regular Verbs",
            "category": "grammar",
            "level": 2,
        },
    ])
    kg.get_user_mastery = MagicMock(return_value=0.7)
    return kg


@pytest.fixture
def mock_logging_service():
    """Mock LoggingService for testing."""
    service = AsyncMock()
    service.log_interaction = AsyncMock(return_value="mock_interaction_id")
    service.log_model_metric = AsyncMock()
    return service


@pytest.fixture
def mock_redis():
    """Mock Redis client."""
    redis = AsyncMock()
    redis.get = AsyncMock(return_value=None)
    redis.set = AsyncMock()
    redis.lpush = AsyncMock()
    redis.lrange = AsyncMock(return_value=[])
    return redis


# ============================================================
# STATE FIXTURES
# ============================================================


@pytest.fixture
def sample_initial_state() -> Dict[str, Any]:
    """Sample initial state for TraceCAG pipeline."""
    return {
        "user_input": "I go to school yesterday.",
        "session_id": "test_session_001",
        "user_id": "test_user_001",
        "input_type": "text",
        "learner_profile": {
            "user_id": "test_user_001",
            "level": "B1",
            "common_errors": ["past_tense"],
            "recent_sessions": [],
        },
        "conversation_history": [],
        "kg_seed_concepts": [],
        "kg_expanded_nodes": [],
        "diagnosis_errors": [],
        "diagnosis_intent": "unknown",
        "diagnosis_confidence": 0.0,
        "models_used": [],
    }


@pytest.fixture
def sample_state_after_diagnosis() -> Dict[str, Any]:
    """State after diagnose_node has run."""
    return {
        "user_input": "I go to school yesterday.",
        "session_id": "test_session_001",
        "user_id": "test_user_001",
        "input_type": "text",
        "learner_profile": {
            "user_id": "test_user_001",
            "level": "B1",
            "common_errors": ["past_tense"],
        },
        "diagnosis_errors": [
            {
                "type": "verb_tense",
                "span": "go",
                "correction": "went",
                "explanation": "Use past tense for actions in the past",
                "severity": "moderate",
            }
        ],
        "diagnosis_intent": "practice",
        "diagnosis_confidence": 0.95,
        "fluency_score": 0.7,
        "grammar_score": 0.6,
        "vocabulary_level": "B1",
        "models_used": ["qwen_diagnosis"],
    }


@pytest.fixture
def sample_learner_profile() -> Dict[str, Any]:
    """Sample learner profile."""
    return {
        "user_id": "test_user_001",
        "level": "B1",
        "common_errors": ["past_tense", "articles"],
        "recent_sessions": [
            {
                "session_id": "prev_session",
                "topics": ["travel"],
                "score": 0.8,
            }
        ],
    }


@pytest.fixture
def sample_grammar_errors() -> list:
    """Sample grammar errors for testing."""
    return [
        {
            "type": "verb_tense",
            "span": "go",
            "correction": "went",
            "explanation": "Use past tense for actions in the past",
            "severity": "moderate",
        },
        {
            "type": "article",
            "span": "school",
            "correction": "the school",
            "explanation": "Use 'the' for specific places",
            "severity": "minor",
        },
    ]


# ============================================================
# DATABASE FIXTURES
# ============================================================


@pytest.fixture
def mock_mongodb():
    """Mock MongoDB database."""
    db = MagicMock()
    db.__getitem__ = MagicMock(return_value=AsyncMock())
    return db


# ============================================================
# ASYNC HELPERS
# ============================================================


@pytest.fixture
def run_async():
    """Helper to run async functions in sync tests."""
    import asyncio

    def _run(coro):
        return asyncio.get_event_loop().run_until_complete(coro)

    return _run


@pytest.fixture(autouse=True)
def mock_redis_client_global(monkeypatch):
    """Globally mock RedisClient to prevent connection blocks during tests."""
    from unittest.mock import AsyncMock
    mock_inst = AsyncMock()
    mock_inst.get = AsyncMock(return_value=None)
    monkeypatch.setattr("api.core.redis_client.RedisClient.get_instance", AsyncMock(return_value=mock_inst))
    monkeypatch.setattr("api.core.redis_client.RedisClient.reconnect", AsyncMock(return_value=mock_inst))
    monkeypatch.setattr("api.core.redis_client.get_redis", AsyncMock(return_value=mock_inst))


@pytest.fixture(autouse=True)
def mock_kg_service_global(monkeypatch):
    """Globally mock get_kg_service to prevent KuzuDB file locks and hangs during tests."""
    from unittest.mock import AsyncMock, MagicMock
    mock_kg = MagicMock()
    mock_kg.get_concepts = MagicMock(return_value={})
    mock_kg.get_seed_concepts_fast = MagicMock(return_value=[])
    mock_kg.semantic_seed_concepts = MagicMock(return_value=[])
    
    class MockKGHits:
        def __init__(self, seed_nodes=None, expanded_nodes=None, paths=None):
            self.seed_nodes = seed_nodes or []
            self.expanded_nodes = expanded_nodes or []
            self.paths = paths or []

    mock_kg.expand = AsyncMock(return_value=MockKGHits())
    mock_kg.expand_best_first = AsyncMock(return_value=MockKGHits())
    mock_kg.get_concept_count = MagicMock(return_value=0)
    mock_kg.record_interaction = AsyncMock()
    mock_kg.get_user_mastery = AsyncMock(return_value={})

    for path in [
        "api.services.kg_service_v3.get_kg_service",
        "api.services.subgraph_hot_cache.get_kg_service",
        "api.services.trace_cag.nodes_v2.get_kg_service",
        "api.services.orchestrator.get_kg_service",
    ]:
        try:
            monkeypatch.setattr(path, lambda: mock_kg)
        except Exception:
            pass


