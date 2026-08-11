"""Compatibility re-export of the canonical TRACE-CAG SCAR implementation."""

from api.services.trace_cag.l1_state_cache import (
    BASE_REQUIRED_DIMENSIONS,
    CERTIFICATE_SCHEMA_VERSION,
    SCAR_WEIGHTS,
    L1Candidate,
    L1Decision,
    L1Request,
    decide_l1_reuse,
)

__all__ = [
    "BASE_REQUIRED_DIMENSIONS",
    "CERTIFICATE_SCHEMA_VERSION",
    "SCAR_WEIGHTS",
    "L1Candidate",
    "L1Decision",
    "L1Request",
    "decide_l1_reuse",
]
