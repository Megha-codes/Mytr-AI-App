from sqlalchemy import Column, DateTime, Float, ForeignKey, Index, String, text
from sqlalchemy.dialects.postgresql import UUID

from ..database import Base


class HealthMetric(Base):
    """Time-series health sample (architecture-v3.md §1.4) — replaces the
    daily-rollup-only `activity_logs` design. Metric-agnostic: `metric` is a
    plain string, not a CHECK-constrained enum, so new metric types (hrv,
    resting_heart_rate, sleep_minutes, weight_kg, ...) need no migration."""

    __tablename__ = "health_metrics"
    __table_args__ = (
        # Idempotent re-sync (§2.5): the app may re-push the same sample
        # (retry, overlapping window) — ON CONFLICT DO NOTHING against this
        # index is what makes POST /health/samples idempotent.
        Index(
            "health_metrics_dedup_idx",
            "user_id", "source", "metric", "external_id",
            unique=True,
            postgresql_where=text("external_id IS NOT NULL"),
            sqlite_where=text("external_id IS NOT NULL"),
        ),
        Index("health_metrics_lookup_idx", "user_id", "metric", "started_at"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    metric = Column(String, nullable=False)
    value = Column(Float, nullable=False)
    unit = Column(String, nullable=False)
    started_at = Column(DateTime(timezone=True), nullable=False)
    ended_at = Column(DateTime(timezone=True), nullable=False)  # == started_at for instantaneous samples
    source = Column(String, nullable=False)  # 'APPLE_HEALTH' | 'HEALTH_CONNECT' | 'FITBIT' | 'MANUAL'
    external_id = Column(String)  # platform sample id, for idempotent re-sync
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=text("now()"))
