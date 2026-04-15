#!/usr/bin/env python3
"""
Color Refactor Script for LexiLingo Flutter App
Replaces hardcoded hex Color() values with AppColors tokens.
Run from: flutter-app/
"""

import os
import re
import glob
from pathlib import Path

# ─── Mapping: hex value → AppColors token ──────────────────────────────────
# Only replaces standalone const hex Color() strings, not generic Colors.xxx
HEX_REPLACEMENTS = {
    # Surfaces / Backgrounds
    "0xFF101922": "AppColors.backgroundDark",
    "0xFFF6F7F8": "AppColors.backgroundLight",
    "0xFFF6F8F8": "AppColors.backgroundLight",  # near-identical alt
    "0xFFFFFFFF": "AppColors.surfaceLight",
    "0xFF1C2A38": "AppColors.surfaceDark",
    "0xFF1C2632": "AppColors.surfaceDarkMuted",
    "0xFF1C2B3A": "AppColors.surfaceDarkElevated",
    "0xFF2A3A4A": "AppColors.surfaceDarkChat",
    "0xFF0F172A": "AppColors.surfaceDarkInput",
    "0xFF112121": "AppColors.accentMintDark",
    # Text
    "0xFF111418": "AppColors.textDark",
    "0xFF617589": "AppColors.textGrey",
    "0xFF94A3B8": "AppColors.textMuted",
    "0xFF9CA3AF": "AppColors.textMuted",
    "0xFF475569": "AppColors.textSlate",
    "0xFF64748B": "AppColors.textSlateLight",
    # Primary
    "0xFF137FEC": "AppColors.primary",
    "0xFF0D5FC4": "AppColors.primaryDark",
    # Grays
    "0xFFEEEEEE": "AppColors.grey200",
    "0xFFE0E0E0": "AppColors.grey300",
    "0xFFBDBDBD": "AppColors.grey400",
    "0xFF9E9E9E": "AppColors.grey500",
    "0xFF757575": "AppColors.grey600",
    "0xFF616161": "AppColors.grey700",
    "0xFF424242": "AppColors.grey800",
    # Slate
    "0xFFE2E8F0": "AppColors.slate200",
    "0xFF1E293B": "AppColors.slate800",
    # Gold / Bronze / Silver
    "0xFFFFD700": "AppColors.gold",
    "0xFFB8720E": "AppColors.goldDark",
    "0xFFB7860E": "AppColors.goldDark",
    "0xFFCD7F32": "AppColors.bronze",
    "0xFFC0C0C0": "AppColors.silver",
    # Orange
    "0xFFFF9800": "AppColors.orange",
    "0xFFFF5722": "AppColors.deepOrange",
    # Error
    "0xFFC62828": "AppColors.errorDark",
    "0xFFEF5350": "AppColors.errorBright",
    # Purple
    "0xFFA855F7": "AppColors.purpleLight",
    # Chat
    "0xFFE8ECEF": "AppColors.chatBgLight",
    # Accentuation
    "0xFF30E8E8": "AppColors.accentMint",
    "0xFF00897B": "AppColors.teal",
    # Reading
    "0xFFF8F5EE": "AppColors.readingPaper",
    "0xFFF4ECD8": "AppColors.readingSepia",
    "0xFFEDE0CC": "AppColors.readingSepiaAlt",
    "0xFF4B3B2A": "AppColors.readingSepiaText",
    "0xFF1A1A2E": "AppColors.readingNight",
    "0xFFE8E0D0": "AppColors.readingNightAlt",
}

# Pattern to match: const Color(0xFF...) or Color(0xFF...) 
PATTERN = re.compile(r"\bconst\s+Color\((0xFF[0-9A-Fa-f]{6})\)|\bColor\((0xFF[0-9A-Fa-f]{6})\)")

IMPORT_LINE = "import 'package:lexilingo_app/core/theme/app_theme.dart';\n"


def needs_import(content: str) -> bool:
    return IMPORT_LINE.strip() not in content


def add_import(content: str) -> str:
    # Find the last import line and insert after
    lines = content.split("\n")
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.startswith("import "):
            last_import_idx = i
    if last_import_idx >= 0:
        lines.insert(last_import_idx + 1, IMPORT_LINE.rstrip())
        return "\n".join(lines)
    return content


def replace_colors(content: str) -> tuple[str, int]:
    count = 0

    def replacer(m):
        nonlocal count
        hex_val = m.group(1) or m.group(2)
        token = HEX_REPLACEMENTS.get(hex_val.upper()) or HEX_REPLACEMENTS.get(hex_val)
        if token:
            count += 1
            return token
        return m.group(0)

    new_content = PATTERN.sub(replacer, content)
    return new_content, count


def process_file(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        original = f.read()

    # Skip the theme file itself
    if "app_theme.dart" in path:
        return {"path": path, "replacements": 0, "skipped": True}

    new_content, count = replace_colors(original)

    if count == 0:
        return {"path": path, "replacements": 0, "skipped": True}

    # Add import if needed and content was changed
    if count > 0 and needs_import(new_content):
        new_content = add_import(new_content)

    with open(path, "w", encoding="utf-8") as f:
        f.write(new_content)

    return {"path": path, "replacements": count, "skipped": False}


def main():
    dart_files = glob.glob("lib/**/*.dart", recursive=True)
    total_replacements = 0
    changed_files = []

    print(f"Processing {len(dart_files)} Dart files...\n")

    for path in sorted(dart_files):
        result = process_file(path)
        if not result["skipped"]:
            changed_files.append(result)
            total_replacements += result["replacements"]
            print(f"  ✅ [{result['replacements']:3d} replacements] {result['path']}")

    print(f"\n{'─'*60}")
    print(f"✅ Done! Modified {len(changed_files)} files")
    print(f"   Total replacements: {total_replacements}")


if __name__ == "__main__":
    main()
