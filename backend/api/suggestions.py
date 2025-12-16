from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime
import json

from database.connection import get_session
from database.models import Product
from services.gemini_service import GeminiService

router = APIRouter()

@router.get("/suggestions/ai")
async def get_ai_suggestions(
    limit: int = 50,
    session: AsyncSession = Depends(get_session),
):
    """
    Get AI-powered suggestions based on purchase history
    """
    print("🔍 [DEBUG] Starting AI Suggestions Request...")

    # 1. Fetch relevant product history
    result = await session.execute(
        select(Product)
        .where(Product.purchase_count > 0)
        .order_by(Product.last_purchased_date.desc())
        .limit(limit)
    )
    products = result.scalars().all()

    print(f"📦 [DEBUG] Database returned {len(products)} products with purchase history.")

    if not products:
        print("⚠️ [DEBUG] No history found. Returning empty list.")
        return {"suggestions": []}

    # 2. Format data for Gemini
    history_context = []
    for p in products:
        days_since = -1
        if p.last_purchased_date:
            days_since = (datetime.utcnow() - p.last_purchased_date).days

        history_context.append({
            "name": p.name,
            "category": p.category,
            "last_bought_days_ago": days_since,
            "typical_frequency_days": p.average_days_between_purchases,
            "purchase_count": p.purchase_count,
            "typical_price": p.typical_price
        })

    print(f"📝 [DEBUG] Sending context to Gemini: {json.dumps(history_context[:2])} ... (trimmed)")

    # 3. Call Gemini
    try:
        gemini = GeminiService()
        print(f"🤖 [DEBUG] Using Model: {gemini.suggestion_model.model_name}")

        suggestions = await gemini.generate_suggestions(history_context)

        print(f"✅ [DEBUG] Gemini returned {len(suggestions)} suggestions.")
        return {"suggestions": suggestions}

    except Exception as e:
        print(f"❌ [DEBUG] CRITICAL GEMINI ERROR: {str(e)}")
        # If Gemini fails, return a dummy item so you know the API was reached
        return {
            "suggestions": [
                {
                    "name": "Error Check Logs",
                    "category": "System",
                    "confidence": 1.0,
                    "reason": f"Check backend console: {str(e)}",
                    "estimatedPrice": 0.0
                }
            ]
        }