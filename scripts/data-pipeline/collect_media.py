#!/usr/bin/env python3
"""
collect_media.py — Copy all referenced media files to backend-service/data/media/,
flatten to one directory, update paths in JSON, write vocabulary_import.json.

Usage:
    python3 collect_media.py
"""

import json
import shutil
from pathlib import Path

SCRIPTS_DIR = Path("/opt/lexilingo/scripts")
INPUT_JSON = SCRIPTS_DIR / "categorized_words_final_merged.json"
BACKEND_DATA = Path("/opt/lexilingo/backend-service/data")
OUTPUT_MEDIA = BACKEND_DATA / "media"
OUTPUT_JSON = BACKEND_DATA / "vocabulary_import.json"


def main() -> None:
    OUTPUT_MEDIA.mkdir(parents=True, exist_ok=True)

    with open(INPUT_JSON, encoding="utf-8") as f:
        data = json.load(f)

    copied = 0
    missing = 0
    skipped_dup = 0

    def copy_file(rel_path: str) -> str | None:
        """Copy file from scripts dir, return flat filename or None if not found."""
        nonlocal copied, missing, skipped_dup
        if not rel_path:
            return None
        src = SCRIPTS_DIR / rel_path
        if not src.exists():
            missing += 1
            return None
        dest = OUTPUT_MEDIA / src.name
        if dest.exists():
            skipped_dup += 1
        else:
            shutil.copy2(src, dest)
            copied += 1
        return src.name

    for item in data:
        # Update audios dict
        audios = item.get("audios", {})
        if isinstance(audios, dict):
            new_audios = {}
            for slot, path in audios.items():
                new_name = copy_file(path) if path else None
                new_audios[slot] = new_name
            item["audios"] = new_audios

        # Update images field (string or list)
        images = item.get("images", "")
        if isinstance(images, list):
            item["images"] = [copy_file(p) for p in images if p]
        elif isinstance(images, str) and images:
            item["images"] = copy_file(images)

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=None, separators=(",", ":"))

    total_in_media = sum(1 for _ in OUTPUT_MEDIA.iterdir())
    total_size_mb = sum(p.stat().st_size for p in OUTPUT_MEDIA.iterdir()) / 1024 / 1024

    print(f"✅ Done!")
    print(f"   Entries : {len(data):,}")
    print(f"   Copied  : {copied:,} files")
    print(f"   Dup skip: {skipped_dup:,} (already existed)")
    print(f"   Missing : {missing:,} (source not found)")
    print(f"   Media dir: {total_in_media:,} files, {total_size_mb:.1f} MB")
    print(f"   JSON out : {OUTPUT_JSON}")


if __name__ == "__main__":
    main()
