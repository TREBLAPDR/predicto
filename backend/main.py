import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

# Import routers and database init
from api.routes import router
from api.products import router as products_router
from api.suggestions import router as suggestions_router # NEW IMPORT
from database.connection import init_db

@asynccontextmanager
async def lifespan(app: FastAPI):
    print("🚀 Starting up... Initializing Database...")
    await init_db()
    yield
    print("🛑 Shutting down...")

app = FastAPI(
    title="Shopping List AI Backend",
    description="Receipt parsing with OCR and AI",
    version="1.0.0",
    lifespan=lifespan,
)

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
app.include_router(suggestions_router, prefix="/api", tags=["suggestions"]) # NEW ROUTER

@app.get("/")
async def root():
    return {
        "message": "Shopping List AI Backend",
        "status": "running",
        "endpoints": {
            "suggestions": "/api/suggestions/ai"
        }
    }

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.get("/ping")
async def ping():
    return {"status": "ok"}