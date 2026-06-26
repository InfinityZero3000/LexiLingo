import re
from pathlib import Path


SCHEMA_DIR = Path(__file__).resolve().parents[1] / "app" / "schemas"


def test_schemas_do_not_use_pydantic_v1_config_or_validators():
    offenders: dict[str, list[str]] = {}

    for path in sorted(SCHEMA_DIR.glob("*.py")):
        source = path.read_text(encoding="utf-8")
        issues: list[str] = []

        if "class Config:" in source:
            issues.append("class Config")
        if re.search(r"from pydantic import .*\bvalidator\b", source):
            issues.append("validator import")
        if re.search(r"@validator\(", source):
            issues.append("@validator")

        if issues:
            offenders[path.name] = issues

    assert not offenders, (
        "Use Pydantic v2 APIs in schemas: ConfigDict/model_config and "
        f"field_validator/model_validator. Offenders: {offenders}"
    )
