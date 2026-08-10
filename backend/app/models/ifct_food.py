from sqlalchemy import Column, DateTime, Numeric, String, text
from sqlalchemy.dialects.postgresql import UUID

from ..database import Base


class IFCTFood(Base):
    """A single IFCT2017 food composition row (migrations/014_ifct_foods.sql),
    diabetes-relevant columns only, per 100g. Populated by
    scripts/import_ifct.py, not written to at request time — this is a
    reference table, not user data.

    No `pg_trgm` GIN index is declared here: it's a Postgres-only performance
    index (see the migration), not something SQLAlchemy's `create_all` needs
    to know about, and the sqlite test harness never creates one either
    (services/nutrition/source_router.py falls back to a plain substring
    search there).
    """

    __tablename__ = "ifct_foods"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    code = Column(String, nullable=False, unique=True)
    name = Column(String, nullable=False)
    energy_kcal = Column(Numeric(7, 1), nullable=False)
    available_carb_g = Column(Numeric(6, 2), nullable=False)
    protein_g = Column(Numeric(6, 2), nullable=False)
    fat_g = Column(Numeric(6, 2), nullable=False)
    fibre_g = Column(Numeric(6, 2), nullable=False)
    sugars_g = Column(Numeric(6, 2), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=text("now()"))
