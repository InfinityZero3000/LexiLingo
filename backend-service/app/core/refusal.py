"""An HTTP refusal a client can act on."""
from typing import Any

from fastapi import HTTPException


def refusal(status_code: int, message: str, details: dict[str, Any]) -> HTTPException:
    """The global handler puts `details` in `error.details`; a dict `detail`
    would reach the client as a Python repr."""
    error = HTTPException(status_code=status_code, detail=message)
    error.details = details
    return error
