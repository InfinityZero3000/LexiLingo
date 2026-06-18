from pathlib import Path

import pytest


AI_SERVICE_ROOT = Path(__file__).resolve().parents[1]
PRODUCTION_ROOTS = (
    AI_SERVICE_ROOT / "api",
    AI_SERVICE_ROOT / "scripts" / "kg_pipeline",
)
DENIED_MARKERS = (
    "learningenglish.voanews.com",
    "bbc.co.uk/learningenglish",
    "learnenglish.britishcouncil.org",
    "dictionary.cambridge.org",
    "oxfordlearnersdictionaries.com",
    "dolenglish.vn",
    "prepedu.com",
    "theieltsworkshop.com",
    "ieltsliz.com",
    "englishclub.com",
    "grammar-monster.com",
    "perfect-english-grammar.com",
    "kaikki.org",
    "conceptnet",
    "tyyppi77/oxford-learner-word-lists",
    "leomauro/cefr-j",
    "web_sources",
    "crawl4ai",
)


def _production_text_files() -> list[Path]:
    files: list[Path] = []
    for root in PRODUCTION_ROOTS:
        files.extend(
            path
            for path in root.rglob("*")
            if path.is_file()
            and path.suffix in {".py", ".txt"}
            and "__pycache__" not in path.parts
        )
    return sorted(files)


@pytest.mark.parametrize("marker", DENIED_MARKERS)
def test_production_pipeline_contains_no_denied_source_markers(marker: str):
    matches = []
    for path in _production_text_files():
        if marker in path.read_text(encoding="utf-8").casefold():
            matches.append(str(path.relative_to(AI_SERVICE_ROOT)))

    assert matches == [], f"{marker!r} remains in production files: {matches}"
