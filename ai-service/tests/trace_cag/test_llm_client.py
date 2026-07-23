from unittest.mock import patch

from api.services.trace_cag import llm_client


def test_provider_client_enables_http2():
    llm_client._HTTPX_CLIENTS.clear()
    with patch("httpx.AsyncClient") as client:
        llm_client._get_httpx_client("groq")
    assert client.call_args.kwargs["http2"] is True
    llm_client._HTTPX_CLIENTS.clear()
