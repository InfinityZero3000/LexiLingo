"""
Crawl4AI-based web crawler for English learning domain content.

Crawls grammar glossaries, idiom lists, phrasal verb lists, IELTS vocab,
and collocation pages. Extracts concept nodes + edges from structured HTML.

Estimated yield:
  - 8-12 target pages × 50-200 items each = ~1 500 additional nodes
  - These are high-quality "curated" nodes vs raw WordNet/Wiktionary

Run after WordNet + Wiktionary stages since it yields fewer but richer nodes.
"""

import asyncio
import csv
import logging
import re
from pathlib import Path
from typing import Dict, List, Tuple

from tqdm import tqdm

from config import (
    CRAWL4AI_CONCURRENCY,
    CRAWL4AI_DELAY,
    PROGRESS_DIR,
    WEB_SOURCES,
)

logger = logging.getLogger(__name__)

# ── Slug helper ────────────────────────────────────────────────────────────
_SLUG_RE = re.compile(r"[^a-z0-9_]")


def _slug(text: str) -> str:
    return _SLUG_RE.sub("_", text.lower().strip())[:80]


# ── Extractors per source type ─────────────────────────────────────────────

def _extract_grammar_glossary(markdown: str) -> List[Dict]:
    """
    Parse a grammar glossary page (e.g., grammar-monster.com/glossary/).
    Expects markdown with lines like: `**Term** — Definition text`
    """
    nodes = []
    for line in markdown.splitlines():
        line = line.strip()
        # Match bold term followed by dash/colon and definition
        m = re.match(r"\*{1,2}([A-Za-z][A-Za-z\s\-\']{2,50})\*{1,2}[\s\—\-:]+(.{10,200})", line)
        if m:
            term = m.group(1).strip()
            definition = m.group(2).strip()[:150]
            nodes.append({
                "id": f"concept:grammar.{_slug(term)}",
                "title": term,
                "keywords": f"{term} grammar {definition[:60]}",
                "level": "B1",
            })
    return nodes


def _extract_phrasal_verbs(markdown: str) -> List[Dict]:
    """Extract phrasal verb entries (verb + particle + meaning)."""
    nodes = []
    # Pattern: "break down — to stop working" or "* break down: fail"
    for line in markdown.splitlines():
        line = line.strip()
        m = re.match(
            r"[*\-]?\s*([a-z]{2,15}\s+(?:up|down|out|off|in|on|away|over|back|through|into|around|about|along|by|for|at|with|after|ahead|apart|aside|out of|up with){1,2})"
            r"[\s\—\-:–]+(.{5,150})",
            line,
            re.IGNORECASE,
        )
        if m:
            pv = m.group(1).strip().lower()
            meaning = m.group(2).strip()[:120]
            nodes.append({
                "id": f"concept:phrasal.{_slug(pv)}",
                "title": pv,
                "keywords": f"{pv} phrasal verb {meaning[:60]}",
                "level": "B1",
            })
    return nodes


def _extract_idioms(markdown: str) -> List[Dict]:
    """Extract idiom entries."""
    nodes = []
    for line in markdown.splitlines():
        line = line.strip()
        m = re.match(
            r"[*\-]?\s*([A-Za-z][a-z\s\'\-,]{5,60})[\s\—\-:–]+(.{10,150})",
            line,
        )
        if m:
            idiom = m.group(1).strip()
            meaning = m.group(2).strip()[:120]
            # Filter out lines that are clearly not idioms
            if any(c.isdigit() for c in idiom) or len(idiom.split()) < 2:
                continue
            nodes.append({
                "id": f"concept:idiom.{_slug(idiom)}",
                "title": idiom,
                "keywords": f"{idiom} idiom expression {meaning[:60]}",
                "level": "B2",
            })
    return nodes


def _extract_collocations(markdown: str) -> List[Dict]:
    """Extract collocation entries."""
    nodes = []
    for line in markdown.splitlines():
        line = line.strip()
        m = re.match(
            r"[*\-]?\s*([a-z][a-z\s]{3,40})[\s\—\-:–]+(.{5,150})",
            line,
            re.IGNORECASE,
        )
        if m:
            colloc = m.group(1).strip()
            context = m.group(2).strip()[:100]
            if len(colloc.split()) < 2:
                continue
            nodes.append({
                "id": f"concept:collocation.{_slug(colloc)}",
                "title": colloc,
                "keywords": f"{colloc} collocation {context[:60]}",
                "level": "B1",
            })
    return nodes


def _extract_generic(markdown: str, source_type: str) -> List[Dict]:
    """Fallback: extract bullet-point lists from any page."""
    nodes = []
    for line in markdown.splitlines():
        line = line.strip()
        m = re.match(r"[*\-]\s+([A-Za-z][A-Za-z\s\'\-,]{3,80})", line)
        if m:
            item = m.group(1).strip()
            nodes.append({
                "id": f"concept:{source_type}.{_slug(item)}",
                "title": item,
                "keywords": f"{item} {source_type}",
                "level": "B1",
            })
    return nodes


_EXTRACTOR_MAP = {
    "grammar_glossary": _extract_grammar_glossary,
    "phrasal_verbs": _extract_phrasal_verbs,
    "idioms": _extract_idioms,
    "collocations": _extract_collocations,
}


def _extract_nodes(markdown: str, source_type: str) -> List[Dict]:
    extractor = _EXTRACTOR_MAP.get(source_type)
    if extractor:
        return extractor(markdown)
    return _extract_generic(markdown, source_type)


# ── Main async crawler ─────────────────────────────────────────────────────

async def _crawl_one(crawler, source: Dict) -> List[Dict]:
    """Crawl one URL and return extracted nodes."""
    try:
        from crawl4ai import CrawlerRunConfig  # type: ignore

        config = CrawlerRunConfig(
            word_count_threshold=20,
            exclude_external_links=True,
            remove_overlay_elements=True,
            wait_for_images=False,
        )
        result = await crawler.arun(url=source["url"], config=config)
        if not result.success:
            logger.warning("Crawl failed for %s: %s", source["url"], result.error_message)
            return []

        markdown = result.markdown.raw_markdown if hasattr(result.markdown, "raw_markdown") else str(result.markdown)
        nodes = _extract_nodes(markdown, source["type"])
        logger.info(
            "  %s → %d nodes extracted (type=%s)",
            source["name"],
            len(nodes),
            source["type"],
        )
        return nodes

    except Exception as exc:
        logger.warning("Error crawling %s: %s", source["url"], exc)
        return []


async def _crawl_all(sources: List[Dict]) -> List[Dict]:
    """Crawl all sources with concurrency limit."""
    try:
        from crawl4ai import AsyncWebCrawler, BrowserConfig  # type: ignore
    except ImportError:
        logger.error("crawl4ai not installed. Run: pip install crawl4ai && crawl4ai-setup")
        return []

    semaphore = asyncio.Semaphore(CRAWL4AI_CONCURRENCY)
    all_nodes: List[Dict] = []

    browser_cfg = BrowserConfig(headless=True, verbose=False)

    async with AsyncWebCrawler(config=browser_cfg) as crawler:
        for source in tqdm(sources, desc="Web sources"):
            async with semaphore:
                nodes = await _crawl_one(crawler, source)
                all_nodes.extend(nodes)
                await asyncio.sleep(CRAWL4AI_DELAY)

    return all_nodes


def extract(nodes_csv: Path, edges_csv: Path, sources: List[Dict] | None = None) -> Tuple[int, int]:
    """
    Crawl web sources and append results to CSV files.

    Args:
        sources: list of source dicts from config; defaults to WEB_SOURCES.
    Returns (node_count, edge_count).
    """
    checkpoint = PROGRESS_DIR / "crawl4ai.done"
    if checkpoint.exists():
        logger.info("Crawl4AI stage already done — skipping (delete %s to re-run)", checkpoint)
        return 0, 0

    sources = sources or WEB_SOURCES
    nodes = asyncio.run(_crawl_all(sources))

    if not nodes:
        logger.warning("Crawl4AI stage produced 0 nodes — check crawl4ai installation")
        checkpoint.touch()
        return 0, 0

    # Deduplicate by ID
    seen: set[str] = set()
    unique_nodes = []
    for n in nodes:
        if n["id"] not in seen:
            seen.add(n["id"])
            unique_nodes.append(n)

    node_count = 0
    with open(nodes_csv, "a", newline="", encoding="utf-8") as nf:
        nw = csv.writer(nf)
        for node in unique_nodes:
            nw.writerow([node["id"], node["title"], node["keywords"], node["level"]])
            node_count += 1

    PROGRESS_DIR.mkdir(parents=True, exist_ok=True)
    checkpoint.touch()
    logger.info("Crawl4AI done — %d unique nodes", node_count)
    return node_count, 0  # edges are added during import stage via type inference
