"""Unit tests for the device JWT audience (architecture-v3.md §2.1).

Device tokens must be a hard-separated audience from user tokens: distinct
`type` claims, `sub` = device_id (not user_id), and a `uid` claim carrying
the owning user. No DB involved — this is pure token encode/decode.
"""

from __future__ import annotations

import uuid

from app.core.security import (
    create_access_token,
    create_device_access_token,
    create_device_refresh_token,
    create_refresh_token,
    decode_token_payload,
    DEVICE_ACCESS_TOKEN_EXPIRE_MINUTES,
    DEVICE_REFRESH_TOKEN_EXPIRE_MINUTES,
    TOKEN_TYPE_ACCESS,
    TOKEN_TYPE_DEVICE_ACCESS,
    TOKEN_TYPE_DEVICE_REFRESH,
    TOKEN_TYPE_REFRESH,
)


def test_device_access_token_claims():
    device_id = uuid.uuid4()
    user_id = uuid.uuid4()
    token = create_device_access_token(device_id, user_id, token_version=3)

    payload = decode_token_payload(token, expected_type=TOKEN_TYPE_DEVICE_ACCESS)
    assert payload is not None
    assert payload["sub"] == str(device_id)
    assert payload["uid"] == str(user_id)
    assert payload["tv"] == 3
    assert payload["type"] == TOKEN_TYPE_DEVICE_ACCESS


def test_device_refresh_token_claims():
    device_id = uuid.uuid4()
    user_id = uuid.uuid4()
    token = create_device_refresh_token(device_id, user_id, token_version=1)

    payload = decode_token_payload(token, expected_type=TOKEN_TYPE_DEVICE_REFRESH)
    assert payload is not None
    assert payload["sub"] == str(device_id)
    assert payload["uid"] == str(user_id)
    assert payload["tv"] == 1


def test_device_access_token_is_not_a_device_refresh_token():
    token = create_device_access_token(uuid.uuid4(), uuid.uuid4())
    assert decode_token_payload(token, expected_type=TOKEN_TYPE_DEVICE_REFRESH) is None


def test_device_token_never_decodes_as_a_user_token():
    """The core §2.1 guarantee: a device token must be rejected everywhere a
    user access/refresh token is expected, and vice versa — distinct `type`
    values, not overlapping ones."""
    device_access = create_device_access_token(uuid.uuid4(), uuid.uuid4())
    device_refresh = create_device_refresh_token(uuid.uuid4(), uuid.uuid4())
    user_access = create_access_token(str(uuid.uuid4()))
    user_refresh = create_refresh_token(str(uuid.uuid4()))

    assert decode_token_payload(device_access, expected_type=TOKEN_TYPE_ACCESS) is None
    assert decode_token_payload(device_access, expected_type=TOKEN_TYPE_REFRESH) is None
    assert decode_token_payload(device_refresh, expected_type=TOKEN_TYPE_ACCESS) is None
    assert decode_token_payload(device_refresh, expected_type=TOKEN_TYPE_REFRESH) is None

    assert decode_token_payload(user_access, expected_type=TOKEN_TYPE_DEVICE_ACCESS) is None
    assert decode_token_payload(user_access, expected_type=TOKEN_TYPE_DEVICE_REFRESH) is None
    assert decode_token_payload(user_refresh, expected_type=TOKEN_TYPE_DEVICE_ACCESS) is None
    assert decode_token_payload(user_refresh, expected_type=TOKEN_TYPE_DEVICE_REFRESH) is None


def test_token_type_constants_are_distinct_from_user_types():
    assert TOKEN_TYPE_DEVICE_ACCESS not in (TOKEN_TYPE_ACCESS, TOKEN_TYPE_REFRESH)
    assert TOKEN_TYPE_DEVICE_REFRESH not in (TOKEN_TYPE_ACCESS, TOKEN_TYPE_REFRESH)
    assert TOKEN_TYPE_DEVICE_ACCESS != TOKEN_TYPE_DEVICE_REFRESH


def test_device_token_lifetimes_match_spec():
    assert DEVICE_ACCESS_TOKEN_EXPIRE_MINUTES == 60           # 1h
    assert DEVICE_REFRESH_TOKEN_EXPIRE_MINUTES == 60 * 24 * 90  # 90d
