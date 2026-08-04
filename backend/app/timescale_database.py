import os
import logging
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base

logger = logging.getLogger(__name__)

TIMESCALE_DATABASE_URL = os.getenv(
    "TIMESCALE_DATABASE_URL",
    "postgresql+asyncpg://mytai_ts_user:mytai_ts_password@localhost:5433/mytai_ts_db",
)

timescale_engine = create_async_engine(TIMESCALE_DATABASE_URL, echo=False)

TimescaleSessionLocal = async_sessionmaker(
    bind=timescale_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

TimescaleBase = declarative_base()


async def get_timescale_db():
    async with TimescaleSessionLocal() as session:
        yield session


async def init_timescale_schema() -> None:
    async with timescale_engine.begin() as conn:
        await conn.execute(text("""
            CREATE TABLE IF NOT EXISTS glucose_readings (
                id              UUID DEFAULT gen_random_uuid(),
                user_id         UUID NOT NULL,
                recorded_at     TIMESTAMPTZ NOT NULL,
                value_mgdl      INTEGER NOT NULL,
                trend           TEXT,
                trend_arrow     TEXT,
                device_type     TEXT NOT NULL,
                is_continuous   BOOLEAN DEFAULT false,
                created_at      TIMESTAMPTZ DEFAULT now(),
                PRIMARY KEY (id, recorded_at)
            )
        """))
        await conn.execute(text("""
            CREATE INDEX IF NOT EXISTS idx_glucose_readings_user_recorded
            ON glucose_readings (user_id, recorded_at DESC)
        """))
        # Architecture v3 §1.3: sensor_id/source + the dedup index the shared
        # poller's ON CONFLICT DO NOTHING ingestion relies on. Mirrors
        # migrations/011_glucose_dedup_and_region.sql — this table is
        # provisioned here on boot rather than through that migration path,
        # so both must stay in sync.
        await conn.execute(text("""
            ALTER TABLE glucose_readings
              ADD COLUMN IF NOT EXISTS sensor_id TEXT,
              ADD COLUMN IF NOT EXISTS source    TEXT NOT NULL DEFAULT 'LIBRE'
        """))
        await conn.execute(text("""
            CREATE UNIQUE INDEX IF NOT EXISTS glucose_readings_dedup_idx
            ON glucose_readings (user_id, sensor_id, recorded_at)
            WHERE sensor_id IS NOT NULL
        """))

    try:
        async with timescale_engine.begin() as conn:
            await conn.execute(text("CREATE EXTENSION IF NOT EXISTS timescaledb"))
            await conn.execute(text("""
                SELECT create_hypertable(
                    'glucose_readings',
                    'recorded_at',
                    if_not_exists => TRUE
                )
            """))
    except SQLAlchemyError as exc:
        logger.warning(
            "TimescaleDB extension is unavailable; using glucose_readings as a normal Postgres table: %s",
            exc,
        )
