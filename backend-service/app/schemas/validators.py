"""Input rules shared by the admin write schemas (never by responses: stored rows must still load)."""

from typing import Any

from pydantic import field_validator

CEFR_LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")


def cefr_field(*names: str) -> Any:
    def check(cls: type, value: str | None) -> str | None:
        if value is None:
            return None
        if value.upper() not in CEFR_LEVELS:
            raise ValueError(f"Level must be one of {list(CEFR_LEVELS)}")
        return value.upper()

    return field_validator(*names)(check)


def not_null(*names: str) -> Any:
    """For partial updates: a field may be left out, but not cleared when its column is required."""

    def check(cls: type, value: Any) -> Any:
        if value is None:
            raise ValueError("This field cannot be null")
        return value

    return field_validator(*names, mode="before")(check)
