import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base

# In production, use env variables. Placeholder URL for now.
# Use postgresql+asyncpg:// for async SQLAlchemy with Postgres
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://mytai_user:mytai_password@localhost:5432/mytai_db")

engine = create_async_engine(DATABASE_URL, echo=True)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

Base = declarative_base()

async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
