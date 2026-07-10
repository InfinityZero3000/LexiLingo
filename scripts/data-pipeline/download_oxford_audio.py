#!/usr/bin/env python3
"""
Download Oxford pronunciation audio (OGG) and convert to MP3.
Source: Oxford_5000_British_English_IPA_Pronunciations.apkg
Target: backend-service/data/media/
"""
import asyncio
import json
import logging
import os
import sqlite3
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

import httpx

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

SCRIPTS_DIR = Path(__file__).parent
APKG_FILE = SCRIPTS_DIR / "Oxford_5000_British_English_IPA_Pronunciations.apkg"
EXTRACT_DIR = SCRIPTS_DIR / "apkg_extracted" / "Oxford_5000"
VOCAB_JSON = SCRIPTS_DIR / "../backend-service/data/vocabulary_import.json"
MEDIA_DIR = SCRIPTS_DIR / "../backend-service/data/media"
CONCURRENT = 10


def extract_apkg():
    if EXTRACT_DIR.exists() and any(EXTRACT_DIR.iterdir()):
        logger.info("Already extracted: %s", EXTRACT_DIR)
        return
    EXTRACT_DIR.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(APKG_FILE, "r") as z:
        z.extractall(EXTRACT_DIR)
    logger.info("Extracted to: %s", EXTRACT_DIR)


def build_word_url_map() -> dict[str, str]:
    db_path = EXTRACT_DIR / "collection.anki21"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT flds FROM notes")
    rows = cursor.fetchall()
    conn.close()

    word_url: dict[str, str] = {}
    for row in rows:
        parts = row[0].split("\x1f")
        if len(parts) < 6:
            continue
        word = parts[1].strip().lower()
        pron_link = parts[5].strip()
        urls = re.findall(r"https://[^\s<\"]+\.ogg", pron_link)
        if urls:
            word_url[word] = urls[0]

    logger.info("Built %d word->URL mappings", len(word_url))
    return word_url


def build_download_list(word_url: dict[str, str]) -> dict[str, str]:
    """Returns {mp3_filename: ogg_url} for files missing in backend/media/."""
    with open(VOCAB_JSON) as f:
        vocab = json.load(f)

    existing = set(os.listdir(MEDIA_DIR))
    to_download: dict[str, str] = {}

    for entry in vocab:
        audios = entry.get("audios")
        if not audios or not isinstance(audios, dict):
            continue
        for fname in audios.values():
            if not fname or fname.startswith("extracted_media/"):
                continue
            if fname in existing:
                continue
            word = entry["word"].lower()
            if word in word_url:
                to_download[fname] = word_url[word]

    logger.info("Files to download: %d", len(to_download))
    return to_download


async def download_and_convert(
    client: httpx.AsyncClient,
    mp3_name: str,
    ogg_url: str,
    semaphore: asyncio.Semaphore,
) -> bool:
    dest = MEDIA_DIR / mp3_name
    if dest.exists():
        return True
    async with semaphore:
        try:
            resp = await client.get(ogg_url, follow_redirects=True, timeout=20)
            if resp.status_code != 200:
                logger.warning("HTTP %d for %s", resp.status_code, ogg_url)
                return False

            with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as tmp:
                tmp.write(resp.content)
                tmp_path = tmp.name

            result = subprocess.run(
                ["ffmpeg", "-y", "-i", tmp_path, "-codec:a", "libmp3lame", "-q:a", "4", str(dest)],
                capture_output=True,
            )
            os.unlink(tmp_path)

            if result.returncode != 0:
                logger.warning("ffmpeg failed for %s: %s", mp3_name, result.stderr[-200:])
                return False

            logger.debug("OK: %s", mp3_name)
            return True

        except Exception as e:
            logger.warning("Error downloading %s: %s", mp3_name, e)
            return False


async def main():
    extract_apkg()
    word_url = build_word_url_map()
    to_download = build_download_list(word_url)

    if not to_download:
        logger.info("Nothing to download — all Oxford audio already present.")
        return

    MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    semaphore = asyncio.Semaphore(CONCURRENT)

    headers = {
        "User-Agent": "Mozilla/5.0 (compatible; LexiLingo/1.0)",
        "Referer": "https://www.oxfordlearnersdictionaries.com/",
    }

    ok = 0
    failed = 0
    async with httpx.AsyncClient(headers=headers) as client:
        tasks = [
            download_and_convert(client, fname, url, semaphore)
            for fname, url in to_download.items()
        ]
        for i, coro in enumerate(asyncio.as_completed(tasks), 1):
            result = await coro
            if result:
                ok += 1
            else:
                failed += 1
            if i % 100 == 0:
                logger.info("Progress: %d/%d (ok=%d, failed=%d)", i, len(tasks), ok, failed)

    logger.info("Done. Downloaded: %d, Failed: %d", ok, failed)


if __name__ == "__main__":
    asyncio.run(main())
