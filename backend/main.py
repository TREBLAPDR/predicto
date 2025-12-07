import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api.routes import router

app = FastAPI(
    title="Shopping List AI Backend",
    description="Receipt parsing with OCR and AI",
    version="1.0.0"
)

# CORS - allow Flutter app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production: specify your Flutter app domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(router, prefix="/api", tags=["receipt"])

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
            "gemini_status": "/api/gemini-status"
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