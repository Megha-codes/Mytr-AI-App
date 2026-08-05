"""ETag support for the device GET endpoints (architecture-v3.md §2.4):
"every GET returns ETag; the device sends If-None-Match and handles 304."
Matters on a metered Pi Zero 2 W link.
"""

from __future__ import annotations

import hashlib
import json

from fastapi import Request, Response
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse


def make_etag(payload) -> str:
    encoded = jsonable_encoder(payload)
    body = json.dumps(encoded, sort_keys=True, separators=(",", ":"), default=str).encode()
    return '"' + hashlib.sha256(body).hexdigest() + '"'


def etag_json_response(request: Request, payload, etag_source=None) -> Response:
    """Computes the ETag over `etag_source` (defaulting to `payload` itself)
    and returns the full `payload` as the body; short-circuits to 304 if the
    client's If-None-Match already matches.

    Pass `etag_source` explicitly whenever `payload` embeds a
    request-time-only field (e.g. `server_time`) that would otherwise change
    on every single call and make the ETag never match twice — defeating the
    point of the cache."""
    etag = make_etag(payload if etag_source is None else etag_source)
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers={"ETag": etag})
    return JSONResponse(content=jsonable_encoder(payload), headers={"ETag": etag})
