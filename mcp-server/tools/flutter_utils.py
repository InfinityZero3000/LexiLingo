"""Flutter utilities — scans screens and routes in the Flutter app."""

import re
from pathlib import Path
from typing import Any


FLUTTER_LIB = Path(__file__).parent.parent.parent / "flutter-app" / "lib"


def list_flutter_screens(feature: str | None = None) -> dict[str, Any]:
    """
    Scan Flutter lib/ for screen files and extract route names.

    Args:
        feature: Optional feature folder to filter, e.g. 'games', 'learning', 'auth'
    """
    if not FLUTTER_LIB.exists():
        return {"error": f"Flutter lib directory not found: {FLUTTER_LIB}"}

    screens_dir = FLUTTER_LIB / "features"
    if not screens_dir.exists():
        screens_dir = FLUTTER_LIB

    # Patterns
    class_pattern = re.compile(r'class (\w+(?:Screen|Page|View))\b')
    route_pattern = re.compile(r"routeName\s*=\s*['\"]([^'\"]+)['\"]|static const routeName\s*=\s*['\"]([^'\"]+)['\"]")

    screens: list[dict] = []

    search_root = screens_dir
    if feature:
        feature_dir = screens_dir / feature
        if feature_dir.exists():
            search_root = feature_dir

    for dart_file in sorted(search_root.rglob("*.dart")):
        # Only screen files
        if not any(part in str(dart_file) for part in ["screen", "page", "view"]):
            continue

        source = dart_file.read_text(encoding="utf-8", errors="ignore")

        class_matches = class_pattern.findall(source)
        if not class_matches:
            continue

        route_match = route_pattern.search(source)
        route_name = None
        if route_match:
            route_name = route_match.group(1) or route_match.group(2)

        rel_path = dart_file.relative_to(FLUTTER_LIB)
        feature_name = rel_path.parts[1] if len(rel_path.parts) > 2 and rel_path.parts[0] == "features" else None

        screens.append({
            "class": class_matches[0],
            "file": str(rel_path),
            "feature": feature_name,
            "route": route_name,
        })

    # Group by feature
    by_feature: dict[str, list] = {}
    for s in screens:
        key = s["feature"] or "root"
        by_feature.setdefault(key, []).append({
            "class": s["class"],
            "file": s["file"],
            "route": s["route"],
        })

    return {
        "total_screens": len(screens),
        "filter_feature": feature,
        "by_feature": by_feature,
    }
