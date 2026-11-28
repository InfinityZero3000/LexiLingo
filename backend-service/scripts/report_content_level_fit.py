"""Level fit and skill balance of the committed course exports, no database needed.

    cd backend-service
    venv/bin/python3 scripts/report_content_level_fit.py \
        --courses content/courses --lexicon ../ai-service/data/lexicon/cefr_vocabulary.jsonl

The lexicon includes CEFR-J rows (commercial licence): measurement only.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.cefr_level_fit import (
    TABLE_HEADER,
    course_balance,
    course_level_fit,
    course_view_from_export,
    format_row,
    load_lexicon_file,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--courses", type=Path, required=True)
    parser.add_argument("--lexicon", type=Path, required=True)
    args = parser.parse_args()

    lexicon = load_lexicon_file(args.lexicon)
    views = [
        course_view_from_export(json.loads(path.read_text(encoding="utf-8")))
        for path in sorted(args.courses.glob("*.json"))
    ]
    print(f"Lexicon: {len(lexicon)} spellings\n\n## Level fit\n\n{TABLE_HEADER}")
    for view in views:
        print(format_row(view["title"], course_level_fit(view, lexicon)))

    print(
        "\n## Balance\n\n"
        "| Course | Declared skill | Dominant measured | Mismatch | Skills measured | Units w/o production | Outcomes | Can-do |\n"
        "|---|---|---|---|---|---|---|---|"
    )
    for view in views:
        b = course_balance(view)
        skills = ", ".join(f"{k} {v}" for k, v in sorted(b["skills"].items(), key=lambda kv: -kv[1]))
        print(
            f"| {view['title']} | {b['declared_skill'] or '-'} | {b['dominant_skill']} "
            f"| {'YES' if b['skill_mismatch'] else 'no'} | {skills} (+{b['unattributed']} unattributed) "
            f"| {len(b['units_without_production'])} | {b['outcome_share'] * 100:.0f}% | {b['can_do_outcomes']} |"
        )


if __name__ == "__main__":
    main()
