import io
import logging
import sys
import types
from importlib import import_module
from unittest.mock import AsyncMock, MagicMock

import httpx
import pytest
from fastapi import HTTPException, UploadFile
from starlette.datastructures import Headers


@pytest.mark.asyncio
async def test_safe_get_offloads_dns_resolution(monkeypatch):
    from app.core import safe_http

    request = httpx.Request("GET", "https://93.184.216.34/article")
    response = httpx.Response(200, content=b"ok", request=request)
    client = MagicMock()
    client.build_request.return_value = request
    client.send = AsyncMock(return_value=response)
    run_sync = AsyncMock(return_value="93.184.216.34")
    monkeypatch.setattr(safe_http.anyio.to_thread, "run_sync", run_sync)

    await safe_http.safe_get(client, "https://example.com/article")

    run_sync.assert_awaited_once_with(safe_http.resolve_pinned_ip, "example.com")


@pytest.mark.asyncio
async def test_ai_service_shared_client_starts_once_and_closes(monkeypatch):
    from app.clients import ai_service_client

    pooled = MagicMock(is_closed=False, aclose=AsyncMock())
    client_factory = MagicMock(return_value=pooled)
    monkeypatch.setattr(ai_service_client.httpx, "AsyncClient", client_factory)
    monkeypatch.setattr(ai_service_client.AIServiceClient, "_shared_client", None)

    ai_service_client.AIServiceClient.start()
    ai_service_client.AIServiceClient.start()
    first = ai_service_client.AIServiceClient()._http()
    second = ai_service_client.AIServiceClient()._http()
    await ai_service_client.AIServiceClient.close()

    assert first is pooled
    assert second is pooled
    client_factory.assert_called_once_with()
    pooled.aclose.assert_awaited_once_with()
    assert ai_service_client.AIServiceClient._shared_client is None


@pytest.mark.asyncio
async def test_translate_word_logs_exception_type_and_keeps_empty_fallback(caplog):
    from app.clients.ai_service_client import AIServiceClient

    http = MagicMock()
    http.get = AsyncMock(side_effect=httpx.ConnectError("offline"))

    with caplog.at_level(logging.WARNING, logger="app.clients.ai_service_client"):
        result = await AIServiceClient(client=http).translate_word(word="hello")

    assert result == {"translation": "", "phonetic": "", "part_of_speech": ""}
    assert "ConnectError" in caplog.text


def test_pdf_extraction_rejects_too_many_pages(monkeypatch):
    from app.routes import admin_courses

    reader = MagicMock()
    reader.pages = [MagicMock()] * (admin_courses._MAX_PDF_PAGES + 1)
    monkeypatch.setattr(admin_courses, "PdfReader", MagicMock(return_value=reader))

    with pytest.raises(HTTPException) as exc_info:
        admin_courses._extract_pdf_text(b"pdf")

    assert exc_info.value.status_code == 413
    assert "page limit" in exc_info.value.detail


def test_pdf_extraction_rejects_excess_text(monkeypatch):
    from app.routes import admin_courses

    page = MagicMock()
    page.extract_text.return_value = "four"
    reader = MagicMock(pages=[page])
    monkeypatch.setattr(admin_courses, "_MAX_PDF_TEXT_CHARS", 3)
    monkeypatch.setattr(admin_courses, "PdfReader", MagicMock(return_value=reader))

    with pytest.raises(HTTPException) as exc_info:
        admin_courses._extract_pdf_text(b"pdf")

    assert exc_info.value.status_code == 413
    assert "text is too large" in exc_info.value.detail


@pytest.mark.asyncio
async def test_pdf_import_offloads_extraction(monkeypatch):
    from app.routes import admin_courses

    file = MagicMock(filename="course.pdf")
    file.read = AsyncMock(return_value=b"pdf")
    run_sync = AsyncMock(return_value="extracted")
    monkeypatch.setattr(admin_courses.anyio.to_thread, "run_sync", run_sync)

    result = await admin_courses._read_import_text(file, pdf_only=True)

    assert result == "extracted"
    run_sync.assert_awaited_once_with(admin_courses._extract_pdf_text, b"pdf")


@pytest.mark.asyncio
async def test_badge_upload_uses_mounted_media_directory(monkeypatch, tmp_path):
    from app.routes import admin_courses

    media_dir = tmp_path / "media"
    media_dir.mkdir()
    monkeypatch.setattr(admin_courses, "_MEDIA_DIR", media_dir)
    file = UploadFile(
        io.BytesIO(b"image"),
        filename="badge.png",
        headers=Headers({"content-type": "image/png"}),
    )

    result = await admin_courses.upload_badge_image(file=file, admin_user=MagicMock())

    assert result.data["url"].startswith("/media/badges/")
    saved = list((media_dir / "badges").iterdir())
    assert len(saved) == 1
    assert saved[0].read_bytes() == b"image"


@pytest.mark.parametrize(
    ("proxy_url", "expected_proxies"),
    [
        (None, {}),
        (
            "http://proxy.example:8080",
            {
                "http": "http://proxy.example:8080",
                "https": "http://proxy.example:8080",
            },
        ),
    ],
)
def test_youtube_transcript_proxy_is_optional(monkeypatch, proxy_url, expected_proxies):
    from app.routes import youtube

    session = MagicMock(proxies={})
    requests_module = types.ModuleType("requests")
    requests_module.Session = MagicMock(return_value=session)
    api = MagicMock()
    api.fetch.return_value = ["caption"]
    transcript_module = types.ModuleType("youtube_transcript_api")
    transcript_module.YouTubeTranscriptApi = MagicMock(return_value=api)
    transcript_module.NoTranscriptFound = type("NoTranscriptFound", (Exception,), {})
    monkeypatch.setitem(sys.modules, "requests", requests_module)
    monkeypatch.setitem(sys.modules, "youtube_transcript_api", transcript_module)
    monkeypatch.setattr(youtube.settings, "YOUTUBE_TRANSCRIPT_PROXY_URL", proxy_url)

    result = youtube._get_transcript_sync("video-id", "en")

    assert result == ["caption"]
    assert session.proxies == expected_proxies
    transcript_module.YouTubeTranscriptApi.assert_called_once_with(http_client=session)


@pytest.mark.asyncio
async def test_youtube_dictionary_request_uses_configured_base_url(monkeypatch):
    from app.routes import youtube

    response = MagicMock(status_code=404)
    http = MagicMock()
    http.get = AsyncMock(return_value=response)
    context = MagicMock()
    context.__aenter__ = AsyncMock(return_value=http)
    context.__aexit__ = AsyncMock(return_value=False)
    ai = MagicMock()
    ai.translate_word = AsyncMock(
        return_value={"translation": "", "phonetic": "", "part_of_speech": ""}
    )
    monkeypatch.setattr(youtube.settings, "DICTIONARY_API_BASE_URL", "https://dict.test/v2/")
    monkeypatch.setattr(youtube.httpx, "AsyncClient", MagicMock(return_value=context))
    monkeypatch.setattr(youtube, "AIServiceClient", MagicMock(return_value=ai))

    await youtube._fetch_word_data("hello")

    http.get.assert_awaited_once_with("https://dict.test/v2/hello")


@pytest.mark.asyncio
async def test_vocabulary_csv_deduplicates_by_word_and_part_of_speech(monkeypatch):
    from app.routes import admin_courses

    csv_text = """word,definition,part_of_speech
hello,Greeting,noun
hello,Action,verb
hello,Repeated action,verb
bye,Farewell,noun
"""
    query_result = MagicMock()
    query_result.tuples.return_value.all.return_value = [("hello", "noun")]
    db = MagicMock()
    db.execute = AsyncMock(return_value=query_result)
    db.commit = AsyncMock()
    inserted = []

    async def bulk_insert(_db, _model, rows, **_kwargs):
        inserted.extend(rows)
        return len(rows)

    monkeypatch.setattr(
        admin_courses, "_read_import_text", AsyncMock(return_value=csv_text)
    )
    monkeypatch.setattr(admin_courses, "_bulk_insert_rows", bulk_insert)

    result = await admin_courses.bulk_import_vocabulary(
        file=MagicMock(), db=db, admin_user=MagicMock()
    )

    assert {(row["word"], row["part_of_speech"]) for row in inserted} == {
        ("hello", "verb"),
        ("bye", "noun"),
    }
    assert result.data["created"] == 2
    assert result.data["skipped"] == 2


_TASK_WRAPPERS = [
    ("app.tasks.reminders", "scan_fsrs_reminders", "_scan_fsrs_reminders", ()),
    ("app.tasks.streak_reminders", "send_streak_alerts", "_send_streak_alerts", ()),
    ("app.tasks.word_of_day", "send_word_of_day", "_run", ()),
    (
        "app.tasks.content_agent",
        "run_content_agent",
        "_run_content_agent",
        ("00000000-0000-0000-0000-000000000001",),
    ),
    (
        "app.tasks.content_agent",
        "cleanup_expired_content_agent_uploads",
        "_cleanup_expired_content_agent_uploads",
        (),
    ),
    (
        "app.tasks.ranking_agent",
        "run_ranking_agent_job",
        "_run_ranking_agent_job",
        ("00000000-0000-0000-0000-000000000001",),
    ),
    ("app.tasks.ranking_agent", "auto_league_reset", "_auto_league_reset", ()),
    (
        "app.tasks.notification_campaign",
        "run_notification_campaign_job",
        "_run_notification_campaign_job",
        ("00000000-0000-0000-0000-000000000001",),
    ),
    ("app.tasks.content_prefetch_schedule", "prefetch_news_task", "_run_news", ()),
    (
        "app.tasks.content_prefetch_schedule",
        "prefetch_youtube_task",
        "_run_youtube",
        (),
    ),
    (
        "app.tasks.content_prefetch_schedule",
        "prefetch_podcasts_task",
        "_run_podcasts",
        (),
    ),
]


@pytest.mark.parametrize("module_name,task_name,body_name,args", _TASK_WRAPPERS)
def test_celery_asyncio_wrapper_closes_db_after_failure(
    monkeypatch, module_name, task_name, body_name, args
):
    module = import_module(module_name)
    close_db = AsyncMock()

    async def fail(*_args):
        raise RuntimeError("task failed")

    monkeypatch.setattr(module, body_name, fail)
    monkeypatch.setattr(module, "close_db", close_db)

    with pytest.raises(RuntimeError, match="task failed"):
        getattr(module, task_name).run(*args)

    close_db.assert_awaited_once_with()
