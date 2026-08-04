"""Regression test for the wrong-LLU-headers bug flagged in
architecture-v3.md §4.3 step 2 / §5.2: libre_service.py's headers said
`version 4.7.0` and were missing accept-encoding/cache-control/connection.
"""

from __future__ import annotations

from app.services.cgm.libre_client import LLU_HEADERS


def test_llu_headers_use_correct_version():
    assert LLU_HEADERS["version"] == "4.16.0"
    assert LLU_HEADERS["version"] != "4.7.0"


def test_llu_headers_include_the_previously_missing_headers():
    assert LLU_HEADERS["accept-encoding"]
    assert LLU_HEADERS["cache-control"]
    assert LLU_HEADERS["connection"]


def test_libre_service_uses_the_shared_corrected_headers():
    """libre_service.py must not carry its own duplicate (and wrong) copy —
    it imports the request functions that use LLU_HEADERS from libre_client."""
    import app.services.cgm.libre_service as libre_service_mod

    assert not hasattr(libre_service_mod, "_LLU_HEADERS")
    assert not hasattr(libre_service_mod, "_LIBRE_BASES")
