import pytest
import os
import numpy as np
from unittest.mock import MagicMock, patch
from api.services.embedding_service_v3 import EmbeddingServiceV3

@pytest.fixture
def clean_env(monkeypatch):
    """Ensure environment is set up properly for embedding tests."""
    monkeypatch.setenv("TRACECAG_PREFER_CLOUD_LLM", "true")
    monkeypatch.setenv("GEMINI_API_KEY", "mock-gemini-key")
    monkeypatch.setenv("V3_FORCE_HASH_EMBEDDINGS", "")

def test_gemini_embeddings_success(clean_env):
    """Test successful Gemini cloud embedding generation and normalization."""
    # embed_content is called once per text (singular `content=` param).
    responses = [
        {"embedding": [0.5, 0.5, 0.5, 0.5]},
        {"embedding": [1.0, 0.0, 0.0, 0.0]},
    ]

    mock_genai = MagicMock()
    mock_genai.embed_content.side_effect = responses

    service = EmbeddingServiceV3()

    with patch.dict("sys.modules", {"google.generativeai": mock_genai}):
        embeddings = service.embed_texts(["hello", "world"])

        # Verify called once per text with singular `content=` parameter.
        assert mock_genai.embed_content.call_count == 2
        mock_genai.embed_content.assert_any_call(
            model="models/text-embedding-004",
            content="hello",
        )
        mock_genai.embed_content.assert_any_call(
            model="models/text-embedding-004",
            content="world",
        )

        # Verify shape (2 texts, 4 dimensions)
        assert embeddings.shape == (2, 4)

        # Verify unit vector normalization (norms should be 1.0)
        norms = np.linalg.norm(embeddings, axis=1)
        np.testing.assert_allclose(norms, [1.0, 1.0], rtol=1e-5)
        np.testing.assert_allclose(embeddings[0], [0.5, 0.5, 0.5, 0.5], rtol=1e-5)
        np.testing.assert_allclose(embeddings[1], [1.0, 0.0, 0.0, 0.0], rtol=1e-5)

def test_gemini_embeddings_fallback_on_api_error(clean_env, monkeypatch):
    """Test fallback to local/deterministic hash embedding on Gemini API failure."""
    # Mock genai to throw an error
    mock_genai = MagicMock()
    mock_genai.embed_content.side_effect = Exception("API Quota exceeded")

    service = EmbeddingServiceV3()
    
    # Force fallback mode internally to avoid attempting SentenceTransformer download
    monkeypatch.setenv("V3_FORCE_HASH_EMBEDDINGS", "true")
    
    with patch.dict("sys.modules", {"google.generativeai": mock_genai}):
        # Should not crash, but fallback successfully
        embeddings = service.embed_texts(["hello", "world"])
        
        # Verify shape (2 texts, 384 dimensions from fallback)
        assert embeddings.shape == (2, 384)
        
        # Verify normalization
        norms = np.linalg.norm(embeddings, axis=1)
        np.testing.assert_allclose(norms, [1.0, 1.0], rtol=1e-5)

def test_gemini_embeddings_skipped_when_disabled(monkeypatch):
    """Test Gemini embedding is skipped when TRACECAG_PREFER_CLOUD_LLM=False."""
    monkeypatch.setenv("TRACECAG_PREFER_CLOUD_LLM", "false")
    monkeypatch.setenv("GEMINI_API_KEY", "mock-gemini-key")
    monkeypatch.setenv("V3_FORCE_HASH_EMBEDDINGS", "true")
    
    mock_genai = MagicMock()
    service = EmbeddingServiceV3()
    
    with patch.dict("sys.modules", {"google.generativeai": mock_genai}):
        embeddings = service.embed_texts(["hello"])
        
        # Verify genai was NOT called
        mock_genai.embed_content.assert_not_called()
        assert embeddings.shape == (1, 384)

def test_gemini_embeddings_skipped_when_key_missing(monkeypatch):
    """Test Gemini embedding is skipped when GEMINI_API_KEY is empty."""
    monkeypatch.setenv("TRACECAG_PREFER_CLOUD_LLM", "true")
    monkeypatch.setenv("GEMINI_API_KEY", "")
    monkeypatch.setenv("V3_FORCE_HASH_EMBEDDINGS", "true")
    
    mock_genai = MagicMock()
    service = EmbeddingServiceV3()
    
    with patch.dict("sys.modules", {"google.generativeai": mock_genai}):
        embeddings = service.embed_texts(["hello"])
        
        # Verify genai was NOT called
        mock_genai.embed_content.assert_not_called()
        assert embeddings.shape == (1, 384)
