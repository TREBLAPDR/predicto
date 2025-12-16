import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")

    # Model 1: Optimized for Vision/Receipt Parsing (Fast & Cost Effective)
    GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-2.0-flash-lite")

    # Model 2: Optimized for Reasoning/Suggestions (Smarter)
    # This allows you to use a different model for the AI suggestions feature
    GEMINI_MODEL_2: str = os.getenv("GEMINI_MODEL_2", "gemini-2.0-flash")

    GEMINI_TEMPERATURE: float = float(os.getenv("GEMINI_TEMPERATURE", "0.1"))
    GEMINI_MAX_TOKENS: int = int(os.getenv("GEMINI_MAX_TOKENS", "2048"))

    DATABASE_URL: str = os.getenv("DATABASE_URL", "")

    @property
    def is_gemini_configured(self) -> bool:
        return bool(self.GEMINI_API_KEY and self.GEMINI_API_KEY != "your_gemini_api_key_here")

settings = Settings()