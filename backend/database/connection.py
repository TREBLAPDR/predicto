import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from database.models import Base

# 1. Get the URL from Render
DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise ValueError("DATABASE_URL is not set. Check your Render Environment Variables.")

# ==========================================
# 🔧 THE RENDER FIX (CRITICAL)
# Render forces "postgresql://", but we need "postgresql+asyncpg://"
# This block fixes the URL automatically.
# ==========================================
if DATABASE_URL.startswith("postgresql://"):
    DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://", 1)

# 2. Create the Async Engine
engine = create_async_engine(
    DATABASE_URL,
    echo=True, # Set to False in production
)

# 3. Create Session Factory
AsyncSessionLocal = sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

# 4. Dependency for API Routes
async def get_session():
    async with AsyncSessionLocal() as session:
        yield session

# 5. Database Initialization (Create Tables)
async def init_db():
    async with engine.begin() as conn:
        # This creates tables if they don't exist
        await conn.run_sync(Base.metadata.create_all)