import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

# Import routers and database init
from api.routes import router
from api.products import router as products_router
from database.connection import init_db

# Lifespan context manager for startup/shutdown logic
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize database tables
    print("🚀 Starting up... Initializing Database...")
    await init_db()
    yield
    # Shutdown: Clean up resources if needed
    print("🛑 Shutting down...")

app = FastAPI(
    title="Shopping List AI Backend",
    description="Receipt parsing with OCR and AI",
    version="1.0.0",
    lifespan=lifespan, # Attach lifespan handler
)

# CORS - allow Flutter app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(router, prefix="/api", tags=["receipt"])
app.include_router(products_router, prefix="/api", tags=["products"])

@app.get("/")
async def root():
    return {
        "message": "Shopping List AI Backend",
        "status": "running",
        "version": "1.0.0",
        "environment": os.getenv("RENDER", "local"),
        "endpoints": {
            "process": "/api/process-advanced",
            "upload": "/api/upload-image",
            "health": "/health",
            "gemini_status": "/api/gemini-status",
            "products": "/api/products",
        }
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "version": "1.0.0",
        "environment": os.getenv("RENDER", "local")
    }

# Render requires this for health checks
@app.get("/ping")
async def ping():
    return {"status": "ok"}