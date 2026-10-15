"""Turn IELTS Listening transcripts into recordings.

A Listening section without audio is a section nobody can answer, and the four
recordings are the one asset an IELTS paper cannot be authored without. The
transcripts are already written, so this synthesises them rather than waiting
for a studio.

Each speaker gets a different accent, because a two-voice conversation read in
one voice is not what the exam sounds like. gTTS is already a dependency of
this service and its `tld` parameter is the cheapest way to get distinguishable
voices — no extra voice models to download and pin.

MP3 frames are concatenated directly. That is enough for a player and avoids
pulling ffmpeg into the image for a job that runs a handful of times.

    # inside the ai-service container
    python scripts/synthesize_ielts_listening.py --input parts.json --out /tmp/ielts

`parts.json` is `[{"part_key": "listening_part_1", "transcript": "..."}]`, which
`backend-service/scripts/attach_ielts_audio.py --dump` writes.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

# Accents, in the order speakers first appear. The exam mixes British,
# Australian and North American voices on purpose.
_ACCENTS = ("co.uk", "com.au", "com", "ca", "co.in", "ie")

_SPEAKER = re.compile(r"^([A-Z][A-Z0-9 '&.-]{1,24}):\s*(.*)$")


def split_turns(transcript: str) -> list[tuple[str, str]]:
    """(speaker, text) in order. A monologue with no labels is one turn."""
    turns: list[tuple[str, str]] = []
    speaker = ""
    buffer: list[str] = []
    for line in transcript.splitlines():
        match = _SPEAKER.match(line.strip())
        if match:
            if buffer:
                turns.append((speaker, " ".join(buffer).strip()))
                buffer = []
            speaker = match.group(1).strip()
            if match.group(2).strip():
                buffer.append(match.group(2).strip())
        elif line.strip():
            buffer.append(line.strip())
    if buffer:
        turns.append((speaker, " ".join(buffer).strip()))
    return [(s, t) for s, t in turns if t]


def synthesize(turns: list[tuple[str, str]]) -> bytes:
    # Each clip already carries a little silence at both ends, which is the gap
    # between turns. Generating an explicit pause would need an encoder, and
    # gTTS refuses text that is only punctuation.
    from gtts import gTTS

    voices: dict[str, str] = {}
    chunks: list[bytes] = []
    for speaker, text in turns:
        if speaker not in voices:
            voices[speaker] = _ACCENTS[len(voices) % len(_ACCENTS)]
        chunks.append(_speak(gTTS, text, voices[speaker]))
        time.sleep(0.4)
    return b"".join(chunks)


def _speak(gTTS, text: str, tld: str) -> bytes:
    import io

    buffer = io.BytesIO()
    gTTS(text=text, lang="en", tld=tld, slow=False).write_to_fp(buffer)
    return buffer.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="JSON list of parts")
    parser.add_argument("--out", required=True, help="directory for the mp3 files")
    args = parser.parse_args()

    parts = json.loads(Path(args.input).read_text())
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest = {}
    for part in parts:
        key = part["part_key"]
        turns = split_turns(part["transcript"])
        speakers = sorted({s for s, _ in turns if s})
        print(f"{key}: {len(turns)} turns, {len(speakers) or 1} voice(s)", flush=True)
        audio = synthesize(turns)
        target = out_dir / f"{key}.mp3"
        target.write_bytes(audio)
        manifest[key] = target.name
        print(f"  wrote {target} ({len(audio) // 1024} kB)", flush=True)

    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
