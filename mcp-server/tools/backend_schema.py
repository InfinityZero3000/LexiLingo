"""Backend schema tool — reads FastAPI routes and returns endpoint summary."""

import re
from pathlib import Path
from typing import Any


ROUTES_DIR = Path(__file__).parent.parent.parent / "backend-service" / "app" / "routes"


def get_backend_schema(filter_path: str | None = None) -> dict[str, Any]:
    """
    Scan backend route files and extract endpoint definitions.

    Args:
        filter_path: Optional path prefix to filter, e.g. '/vocabulary', '/games'
    """
    if not ROUTES_DIR.exists():
        return {"error": f"Routes directory not found: {ROUTES_DIR}"}

    # HTTP method decorators
    method_pattern = re.compile(
        r'@router\.(get|post|put|patch|delete|head)\s*\(\s*["\']([^"\']+)["\']',
        re.IGNORECASE,
    )
    # Router prefix
    prefix_pattern = re.compile(r'prefix\s*=\s*["\']([^"\']+)["\']')
    # Function name after decorator
    func_pattern = re.compile(r'async def (\w+)|def (\w+)')

    endpoints: list[dict] = []

    for route_file in sorted(ROUTES_DIR.glob("*.py")):
        if route_file.name.startswith("_"):
            continue

        source = route_file.read_text(encoding="utf-8")
        lines = source.splitlines()

        # Extract router prefix
        prefix_match = prefix_pattern.search(source)
        prefix = prefix_match.group(1) if prefix_match else f"/{route_file.stem}"

        # Walk lines to find @router.method decorators and the following function
        i = 0
        while i < len(lines):
            line = lines[i]
            m = method_pattern.search(line)
            if m:
                method = m.group(1).upper()
                path = m.group(2)
                full_path = prefix + path

                # Find the next def/async def
                func_name = None
                for j in range(i + 1, min(i + 10, len(lines))):
                    fm = func_pattern.search(lines[j])
                    if fm:
                        func_name = fm.group(1) or fm.group(2)
                        break

                endpoints.append({
                    "method": method,
                    "path": full_path,
                    "handler": func_name or "unknown",
                    "file": route_file.name,
                })
            i += 1

    if filter_path:
        filter_path = filter_path.rstrip("/")
        endpoints = [e for e in endpoints if e["path"].startswith(filter_path)]

    # Group by file/tag
    by_tag: dict[str, list] = {}
    for ep in endpoints:
        tag = ep["file"].replace(".py", "")
        by_tag.setdefault(tag, []).append({
            "method": ep["method"],
            "path": ep["path"],
            "handler": ep["handler"],
        })

    return {
        "total_endpoints": len(endpoints),
        "filter": filter_path,
        "tags": by_tag,
    }
