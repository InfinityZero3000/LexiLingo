#!/usr/bin/env python3
"""Give every font in a Flutter web build a content-hashed name so it can be cached forever.

Fonts keep fixed names across builds (MaterialIcons is tree-shaken per build), so they can
only be marked immutable under a name that changes with their bytes. The engine finds fonts
through FontManifest.json, which stays no-cache, so rewriting it is enough. The originals
are kept so a tab still running the previous build can load them.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path

HASH_LEN = 12


def fingerprint(build_dir: Path) -> list[tuple[str, str]]:
    assets = build_dir / "assets"
    manifest_path = assets / "FontManifest.json"
    manifest = json.loads(manifest_path.read_text())
    renamed: list[tuple[str, str]] = []
    for family in manifest:
        for font in family["fonts"]:
            asset = font["asset"]
            source = assets / asset
            digest = hashlib.sha256(source.read_bytes()).hexdigest()[:HASH_LEN]
            if source.stem.endswith(f".{digest}"):
                continue
            hashed = source.with_name(f"{source.stem}.{digest}{source.suffix}")
            shutil.copyfile(source, hashed)
            font["asset"] = hashed.relative_to(assets).as_posix()
            renamed.append((asset, font["asset"]))
    manifest_path.write_text(json.dumps(manifest, separators=(",", ":")))
    return renamed


def main() -> int:
    build_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web")
    for old, new in fingerprint(build_dir):
        print(f"{old} -> {new}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
