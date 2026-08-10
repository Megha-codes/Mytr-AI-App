"""Shared test setup.

Supplies a dummy JWT_SECRET *before* any app module is imported (config /
security read env at import time), so the suite runs fully offline with no
real Postgres / Timescale / credentials.
"""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone

# Must be set before importing app.* (security.py raises if JWT_SECRET is
# missing; config reads env at import).
os.environ.setdefault("JWT_SECRET", "test-secret-not-used-anywhere-real")

from sqlalchemy import event, text
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

# `postgresql.UUID(as_uuid=True)` only needs a Python-side bind processor on
# dialects without native UUID support. asyncpg (production) has native UUID
# support and accepts the plain str the app already produces (security.py's
# `_create_token` always JSON-encodes the JWT `sub` claim as str), so this
# patch is inert against the real Postgres dialect. SQLite (used below to
# stand in for Postgres in route-level tests) falls back to a processor that
# requires an actual `uuid.UUID` instance, which the app's own
# `User.id == payload.get("sub")` comparisons don't provide — coerce it here
# instead of touching that production code.
_orig_uuid_bind_processor = PG_UUID.bind_processor


def _sqlite_safe_bind_processor(self, dialect):
    processor = _orig_uuid_bind_processor(self, dialect)
    if processor is None:
        return None

    def process(value):
        if isinstance(value, str):
            value = uuid.UUID(value)
        return processor(value)

    return process


PG_UUID.bind_processor = _sqlite_safe_bind_processor

# SQLite has no native tz-aware datetime storage, so `DateTime(timezone=True)`
# columns round-trip as naive on sqlite even though Postgres/asyncpg (real
# TIMESTAMPTZ) always returns tz-aware UTC datetimes. Every value written
# through this app is already UTC (there is no other timezone in play at the
# storage layer), so re-attaching UTC on read makes sqlite match Postgres's
# actual behavior instead of introducing a naive/aware split that doesn't
# exist against the real database.
from sqlalchemy.dialects.sqlite.base import DATETIME as _SQLiteDATETIME

_orig_datetime_result_processor = _SQLiteDATETIME.result_processor


def _tz_aware_result_processor(self, dialect, coltype):
    processor = _orig_datetime_result_processor(self, dialect, coltype)
    if processor is None or not self.timezone:
        return processor

    def process(value):
        result = processor(value)
        if result is not None and result.tzinfo is None:
            result = result.replace(tzinfo=timezone.utc)
        return result

    return process


_SQLiteDATETIME.result_processor = _tz_aware_result_processor


async def build_sqlite_db():
    """In-memory SQLite standing in for Postgres in route-level tests.

    Registers the two Postgres-only SQL functions (`now()`, `gen_random_uuid()`)
    the schema's `server_default`s rely on, so unmodified production routes
    that never set those columns explicitly still work unchanged.

    Creates only the tables these tests actually need, by explicit list —
    `Base` is the *whole app's* declarative base, shared with modules (e.g.
    models/inference.py, models/meal_log.py) that use Postgres-only types
    like JSONB. Once anything imports one of those — e.g. test_main_lifecycle.py
    importing app.main — an unscoped `Base.metadata.create_all()` starts
    failing to compile against sqlite for every test that runs after it,
    depending on file collection order. Passing `tables=` sidesteps that
    entirely instead of depending on what has or hasn't been imported yet.
    """
    from app.database import Base
    from app.models.user import (
        CGMDevice, InsulinProfile, LifestyleBaseline, LoginAttempt, User, WearableDevice,
    )
    from app.models.activity import ActivityLog
    from app.models.device import Device, DevicePairingCode
    from app.models.secret import EncryptedSecret
    from app.models.health_metric import HealthMetric
    from app.models.ifct_food import IFCTFood
    # Not added to `tables` below (recommendation_audit_log itself is never
    # created here) — imported so its Table object exists in Base.metadata
    # at all. MealLog.recommendation_id is a ForeignKey to it, and the ORM
    # insert path (app/api/nutrition.py's `db.add(MealLog(...))`) walks the
    # *whole* metadata graph to order the flush, not just the tables this
    # fixture creates — without this import that walk raises
    # NoReferencedTableError before a single query even runs, for a table
    # nothing here is trying to touch.
    import app.models.inference  # noqa: F401

    tables = [
        User.__table__, InsulinProfile.__table__, CGMDevice.__table__,
        LoginAttempt.__table__, WearableDevice.__table__, LifestyleBaseline.__table__,
        ActivityLog.__table__, Device.__table__, DevicePairingCode.__table__,
        EncryptedSecret.__table__, HealthMetric.__table__, IFCTFood.__table__,
    ]

    engine = create_async_engine("sqlite+aiosqlite:///:memory:")

    @event.listens_for(engine.sync_engine, "connect")
    def _register_pg_shims(dbapi_conn, _):
        dbapi_conn.create_function("now", 0, lambda: datetime.now(timezone.utc).isoformat())
        dbapi_conn.create_function("gen_random_uuid", 0, lambda: uuid.uuid4().hex)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all, tables=tables)
        # meal_logs (models/meal_log.py) can't join the `tables=` list above —
        # its `food_items` column is Postgres-only JSONB, which has no sqlite
        # compiler at all (UnsupportedCompilationError), unlike the UUID/JSON
        # types elsewhere that at least degrade gracefully. This hand-written,
        # sqlite-compatible mirror of migrations/002_meal_logs.sql (+ 005's
        # total_fiber_g, + 015's nutrition_source/nutrition_verified) stands
        # in instead — full column set, since both readers (app/api/
        # device_data.py, raw SQL) and the ORM write path (app/api/
        # nutrition.py's `db.add(MealLog(...))`) need every column the
        # mapped model declares, not just the ones any one caller touches.
        await conn.execute(text("""
            CREATE TABLE IF NOT EXISTS meal_logs (
                id TEXT PRIMARY KEY DEFAULT (gen_random_uuid()),
                user_id TEXT NOT NULL,
                meal_time TIMESTAMP NOT NULL,
                food_items TEXT NOT NULL,
                recognition_confidence NUMERIC,
                user_corrected BOOLEAN DEFAULT 0,
                user_correction_notes TEXT,
                total_calories INTEGER,
                total_carbs_g NUMERIC,
                total_protein_g NUMERIC,
                total_fat_g NUMERIC,
                total_fiber_g NUMERIC,
                glycaemic_load NUMERIC,
                nutrition_source TEXT,
                nutrition_verified BOOLEAN,
                recommendation_id TEXT,
                post_meal_glucose_1hr INTEGER,
                post_meal_glucose_2hr INTEGER,
                glucose_outcome TEXT,
                created_at TIMESTAMP
            )
        """))

    session_factory = async_sessionmaker(bind=engine, expire_on_commit=False)
    return engine, session_factory


async def build_sqlite_timescale_db():
    """In-memory SQLite standing in for TimescaleDB — glucose_readings lives
    on a separate `TimescaleBase` (see app/timescale_database.py), so it
    needs its own engine/session, not `build_sqlite_db`'s."""
    from app.timescale_database import TimescaleBase
    import app.models.glucose_reading  # noqa: F401 - registers glucose_readings

    engine = create_async_engine("sqlite+aiosqlite:///:memory:")

    @event.listens_for(engine.sync_engine, "connect")
    def _register_pg_shims(dbapi_conn, _):
        dbapi_conn.create_function("now", 0, lambda: datetime.now(timezone.utc).isoformat())
        dbapi_conn.create_function("gen_random_uuid", 0, lambda: uuid.uuid4().hex)

    async with engine.begin() as conn:
        await conn.run_sync(TimescaleBase.metadata.create_all)

    session_factory = async_sessionmaker(bind=engine, expire_on_commit=False)
    return engine, session_factory


async def make_user(session_factory, email: str, token_version: int = 0):
    from app.models.user import User

    user = User(
        id=uuid.uuid4(),
        email=email,
        password_hash="x",
        email_verified=True,
        created_at=datetime.now(timezone.utc),
        token_version=token_version,
    )
    async with session_factory() as session:
        session.add(user)
        await session.commit()
        await session.refresh(user)
    return user
