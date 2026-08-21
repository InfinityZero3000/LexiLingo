"""Move Listening recordings into the media directory and onto the paper.

Two steps, because the synthesiser lives in ai-service (that is where gTTS is
installed) and the test row lives here:

    # 1. here — write the transcripts out
    venv/bin/python3 scripts/attach_ielts_audio.py --dump /tmp/parts.json

    # 2. in the ai-service container — turn them into mp3 files
    python scripts/synthesize_ielts_listening.py --input parts.json --out /tmp/ielts

    # 3. here — file them and point the paper at them
    venv/bin/python3 scripts/attach_ielts_audio.py --attach /tmp/ielts

Publishing happens only if the paper validates once the audio is attached, so a
missing recording still blocks the test rather than shipping a silent section.
"""

import argparse
import asyncio
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select
from sqlalchemy.orm.attributes import flag_modified

from app.core.database import AsyncSessionLocal
from app.models.ielts import IeltsTest
from app.routes.admin_ielts import _MEDIA_DIR, validate_test_content

TITLE = "IELTS Academic Practice Test 1"


def _media_target() -> tuple[Path, str]:
    """Mirror the admin upload endpoint: the volume in the container, static
    outside it, so a URL produced here resolves the same way."""
    if _MEDIA_DIR.is_dir():
        return _MEDIA_DIR / "ielts", "/media/ielts"
    fallback = Path(__file__).resolve().parent.parent / "static" / "ielts"
    return fallback, "/static/ielts"


def _listening_parts(content: dict) -> list[dict]:
    return [
        part
        for section in content.get("sections") or []
        if (section.get("skill") or "").lower() == "listening"
        for part in section.get("parts") or []
        if isinstance(part, dict)
    ]


async def dump(path: Path) -> int:
    async with AsyncSessionLocal() as db:
        test = (
            await db.execute(select(IeltsTest).where(IeltsTest.title == TITLE))
        ).scalar_one_or_none()
        if test is None:
            print(f"{TITLE!r} is not seeded yet — run scripts/seed_ielts_test.py first.")
            return 1
        parts = [
            {"part_key": part.get("part_key") or f"listening_part_{part.get('order')}",
             "transcript": part.get("transcript") or ""}
            for part in _listening_parts(test.content or {})
        ]
    missing = [p["part_key"] for p in parts if not p["transcript"].strip()]
    path.write_text(json.dumps(parts, indent=2))
    print(f"wrote {len(parts)} transcript(s) to {path}")
    if missing:
        print(f"  no transcript for: {', '.join(missing)}")
    return 0


async def attach(source: Path) -> int:
    target_dir, url_prefix = _media_target()
    target_dir.mkdir(parents=True, exist_ok=True)

    async with AsyncSessionLocal() as db:
        test = (
            await db.execute(select(IeltsTest).where(IeltsTest.title == TITLE))
        ).scalar_one_or_none()
        if test is None:
            print(f"{TITLE!r} is not seeded yet.")
            return 1

        content = test.content or {}
        attached = 0
        for part in _listening_parts(content):
            key = part.get("part_key") or f"listening_part_{part.get('order')}"
            candidate = source / f"{key}.mp3"
            if not candidate.is_file():
                print(f"  {key}: no {candidate.name} in {source}")
                continue
            name = f"{key}.mp3"
            shutil.copyfile(candidate, target_dir / name)
            part["audio_url"] = f"{url_prefix}/{name}"
            attached += 1
            print(f"  {key} -> {part['audio_url']} ({candidate.stat().st_size // 1024} kB)")

        problems = validate_test_content(content, skill_scope=test.skill_scope)
        test.content = content
        flag_modified(test, "content")
        test.is_published = not problems
        await db.commit()

    print(f"\nattached {attached} recording(s); published: {not problems}")
    for problem in problems:
        print(f"  - {problem}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--dump", metavar="FILE", help="write the transcripts to a JSON file")
    group.add_argument("--attach", metavar="DIR", help="file the mp3 files in DIR")
    args = parser.parse_args()
    if args.dump:
        return asyncio.run(dump(Path(args.dump)))
    return asyncio.run(attach(Path(args.attach)))


if __name__ == "__main__":
    raise SystemExit(main())
