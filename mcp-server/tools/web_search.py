"""Tavily web search tool for real-time information lookup."""

import os
import httpx
from typing import Any


TAVILY_API_URL = "https://api.tavily.com/search"


async def search_web(
    query: str,
    max_results: int = 5,
    search_depth: str = "basic",
) -> dict[str, Any]:
    """
    Search the web using Tavily API.

    Args:
        query: Search query string
        max_results: Number of results (1-10)
        search_depth: "basic" (fast) or "advanced" (deeper, costs more credits)
    """
    api_key = os.getenv("TAVILY_API_KEY")
    if not api_key:
        return {"error": "TAVILY_API_KEY not set in environment"}

    max_results = max(1, min(10, max_results))

    payload = {
        "api_key": api_key,
        "query": query,
        "max_results": max_results,
        "search_depth": search_depth,
        "include_answer": True,
        "include_raw_content": False,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(TAVILY_API_URL, json=payload)
        response.raise_for_status()
        data = response.json()

    results = []
    for item in data.get("results", []):
        results.append({
            "title": item.get("title", ""),
            "url": item.get("url", ""),
            "content": item.get("content", ""),
            "score": round(item.get("score", 0), 3),
        })

    return {
        "query": query,
        "answer": data.get("answer"),
        "results": results,
        "total": len(results),
    }
