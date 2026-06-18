"""Operator CLI for the admin content-agent API."""

from __future__ import annotations

import argparse
import json
import os
import sys

import httpx


def _request(method: str, path: str, *, payload: dict | None = None) -> dict:
    base_url = os.getenv("CONTENT_AGENT_BACKEND_URL", "http://localhost:8000/api/v1")
    token = os.getenv("CONTENT_AGENT_ADMIN_TOKEN", "")
    if not token:
        raise RuntimeError("CONTENT_AGENT_ADMIN_TOKEN is required")
    response = httpx.request(
        method,
        f"{base_url.rstrip('/')}{path}",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage CEFR content-agent jobs")
    commands = parser.add_subparsers(dest="command", required=True)

    generate = commands.add_parser("generate")
    generate.add_argument("--levels", nargs="+", required=True)
    generate.add_argument("--sources", nargs="+", default=["existing_cefr"])
    generate.add_argument("--upload-id")
    generate.add_argument("--title-focus")
    generate.add_argument("--topic-focus", nargs="*", default=[])
    generate.add_argument("--units-per-course", type=int, default=3)
    generate.add_argument("--lessons-per-unit", type=int, default=3)
    generate.add_argument("--words-per-lesson", type=int, default=10)
    generate.add_argument("--exercises-per-lesson", type=int, default=10)
    generate.add_argument("--revision", action="store_true")
    mode = generate.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply-on-success", action="store_true")

    for name in ("status", "apply", "retry", "cancel"):
        command = commands.add_parser(name)
        command.add_argument("job_id")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command == "generate":
        payload = {
            "levels": args.levels,
            "sources": args.sources,
            "upload_id": args.upload_id,
            "title_focus": args.title_focus,
            "topic_focus": args.topic_focus,
            "units_per_course": args.units_per_course,
            "lessons_per_unit": args.lessons_per_unit,
            "words_per_lesson": args.words_per_lesson,
            "exercises_per_lesson": args.exercises_per_lesson,
            "revision": args.revision,
            "apply_on_success": args.apply_on_success,
        }
        result = _request("POST", "/admin/content-agent/jobs", payload=payload)
    elif args.command == "status":
        result = _request("GET", f"/admin/content-agent/jobs/{args.job_id}")
    else:
        result = _request(
            "POST", f"/admin/content-agent/jobs/{args.job_id}/{args.command}"
        )
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, httpx.HTTPError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
