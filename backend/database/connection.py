import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, declarative_base # Added declarative_base

# 1. Get the URL
DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise ValueError("DATABASE_URL is not set")

# RENDER FIX
if DATABASE_URL.startswith("postgresql://"):
    DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://", 1)

# 2. Create Engine
engine = create_async_engine(DATABASE_URL, echo=True)

# 3. Create Session Factory
AsyncSessionLocal = sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

# 4. Define Base HERE (Breaks the circular import)
Base = declarative_base()

# 5. Dependency
async def get_session():
    async with AsyncSessionLocal() as session:
        yield session

# 6. Init DB
async def init_db():
    # IMPORT MODELS HERE (Local import prevents circular dependency)
    # We need to import them so SQLAlchemy knows the tables exist before creating them.
    from database import models

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)