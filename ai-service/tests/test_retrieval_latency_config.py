from unittest.mock import MagicMock

from api.services import retrieval_service_v3 as module


def test_graph_analytics_can_be_disabled_for_latency(monkeypatch):
    monkeypatch.setenv("V3_ENABLE_GRAPH_ANALYTICS", "false")
    monkeypatch.setattr(module, "get_graph_analytics", MagicMock())
    precompute = MagicMock()
    monkeypatch.setattr(module.RetrievalServiceV3, "_precompute_analytics", precompute)

    service = module.RetrievalServiceV3(MagicMock())

    precompute.assert_not_called()
    assert service.config.use_centrality_ranking is False
    assert service.config.use_community_detection is False
