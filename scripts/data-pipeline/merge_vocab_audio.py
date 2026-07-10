#!/usr/bin/env python3
"""
Merge vocabulary audio and image files from Anki deck folders into categorized_words_final.json.

Restructures `audios` from a single string to a structured dict:
  {
    "pronunciation": "folder/word.mp3",
    "example":       "folder/word_example.mp3",
    "meaning":       "folder/word_meaning.mp3"
  }

Updates `images` from an empty string to a relative path when found.
Writes result to categorized_words_final_merged.json.
"""

import json
import os
import re
from pathlib import Path
from collections import defaultdict

SCRIPTS_DIR = Path(__file__).parent

INPUT_JSON = SCRIPTS_DIR / "categorized_words_final.json"
OUTPUT_JSON = SCRIPTS_DIR / "categorized_words_final_merged.json"

# Source folders to scan (relative to SCRIPTS_DIR), highest-priority first.
SOURCE_FOLDERS = [
    "extracted_media",
    "4000_Essential_English_Words_all_books_en-ko_M4R4M",
    "4000_Essential_English_Words_1_en-pl_M4R4M_KrisZet",
    "English_C1_Words_Idioms_Phrasal_Verbs_American_Accent",
    "550_Phrasal_Verbs_-_Part_1_Ingls_-_Portugus",
    "500_English_wordswith_pictures_and_audio",
    "Barrons_Basic_Word_List_1500_words_for_the_PSAT_SAT_etc",
]

# Regex that matches Anki-generated numeric timestamp suffixes like _1392933884419
ANKI_SUFFIX_RE = re.compile(r"_\d{10,}$")

AUDIO_EXTS = {".mp3", ".wav", ".ogg", ".m4a"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}


def normalize(word: str) -> str:
    """Lowercase and strip for consistent matching."""
    return word.strip().lower()


def build_folder_index(folder: Path) -> dict:
    """
    Scan a folder and return a dict:
      normalized_word -> {
          "pronunciation": relative_path_str | None,
          "example":       relative_path_str | None,
          "meaning":       relative_path_str | None,
          "image":         relative_path_str | None,
      }

    Priority: clean `word.mp3` > anki-suffixed `word_TIMESTAMP.mp3`.
    """
    if not folder.is_dir():
        return {}

    # Collect all files, skipping unnamed recordings (rec*.mp3) and system files
    audio_map: dict[str, dict] = defaultdict(lambda: {
        "pronunciation": None,
        "example": None,
        "meaning": None,
        "image": None,
    })

    for filepath in folder.iterdir():
        if not filepath.is_file():
            continue

        name = filepath.name
        stem = filepath.stem
        suffix = filepath.suffix.lower()

        # Skip unnamed recordings and hidden/system files
        if stem.startswith("rec") and suffix in AUDIO_EXTS:
            continue
        if stem.startswith("_") or stem.startswith("."):
            continue
        if stem.startswith("paste-"):
            continue

        rel_path = str(filepath.relative_to(SCRIPTS_DIR))

        if suffix in IMAGE_EXTS:
            # Strip Anki timestamp suffix to get word key
            word_key = normalize(ANKI_SUFFIX_RE.sub("", stem))
            entry = audio_map[word_key]
            # Prefer clean filenames over Anki-timestamped ones
            if entry["image"] is None or not ANKI_SUFFIX_RE.search(stem):
                entry["image"] = rel_path

        elif suffix in AUDIO_EXTS:
            # Detect _example and _meaning variants
            if stem.endswith("_example"):
                word_key = normalize(stem[: -len("_example")])
                entry = audio_map[word_key]
                if entry["example"] is None:
                    entry["example"] = rel_path
            elif stem.endswith("_meaning"):
                word_key = normalize(stem[: -len("_meaning")])
                entry = audio_map[word_key]
                if entry["meaning"] is None:
                    entry["meaning"] = rel_path
            else:
                # Pronunciation file: strip Anki timestamp if present
                clean_stem = ANKI_SUFFIX_RE.sub("", stem)
                word_key = normalize(clean_stem)
                entry = audio_map[word_key]
                is_anki = bool(ANKI_SUFFIX_RE.search(stem))
                # Prefer clean file over Anki-timestamped fallback
                if entry["pronunciation"] is None or not is_anki:
                    entry["pronunciation"] = rel_path

    return dict(audio_map)


def merge():
    print(f"Reading {INPUT_JSON} ...")
    with open(INPUT_JSON, encoding="utf-8") as f:
        entries = json.load(f)

    print(f"Loaded {len(entries)} vocabulary entries.")

    # Build combined index from all source folders (first folder wins per slot)
    combined: dict[str, dict] = defaultdict(lambda: {
        "pronunciation": None,
        "example": None,
        "meaning": None,
        "image": None,
    })

    for folder_name in SOURCE_FOLDERS:
        folder = SCRIPTS_DIR / folder_name
        if not folder.is_dir():
            print(f"  [skip] {folder_name} — not found")
            continue
        print(f"  Indexing {folder_name} ...")
        folder_index = build_folder_index(folder)
        print(f"    → {len(folder_index)} unique word keys")
        for word_key, data in folder_index.items():
            entry = combined[word_key]
            # Fill slots that aren't taken yet
            for slot in ("pronunciation", "example", "meaning", "image"):
                if entry[slot] is None and data[slot] is not None:
                    entry[slot] = data[slot]

    print(f"\nCombined index covers {len(combined)} unique word keys.")

    # Apply to JSON entries
    matched = 0
    for item in entries:
        word = item.get("word", "")
        key = normalize(word)

        media = combined.get(key)

        # --- audios field ---
        existing_audio = item.get("audios", "")

        if media and any(media[s] for s in ("pronunciation", "example", "meaning")):
            new_audios: dict = {}
            if media["pronunciation"]:
                new_audios["pronunciation"] = media["pronunciation"]
            elif existing_audio:
                # Keep original string as pronunciation fallback
                new_audios["pronunciation"] = existing_audio
            if media["example"]:
                new_audios["example"] = media["example"]
            if media["meaning"]:
                new_audios["meaning"] = media["meaning"]
            item["audios"] = new_audios
            matched += 1
        else:
            # No structured audio found — wrap existing string in dict form
            if existing_audio:
                item["audios"] = {"pronunciation": existing_audio}
            else:
                item["audios"] = {}

        # --- images field ---
        existing_image = item.get("images", "")
        if media and media["image"]:
            item["images"] = media["image"]
        elif not existing_image:
            item["images"] = ""

    print(f"Matched audio/images for {matched} / {len(entries)} entries.")

    print(f"\nWriting {OUTPUT_JSON} ...")
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, indent=2)

    print("Done.")


if __name__ == "__main__":
    merge()
