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
    print("🔍 [DEBUG] Starting AI Suggestions Request...")

    # 1. Fetch relevant product history
    result = await session.execute(
        select(Product)
        .where(Product.purchase_count > 0)
        .order_by(Product.last_purchased_date.desc())
        .limit(limit)
    )
    products = result.scalars().all()

    print(f"📦 [DEBUG] Database returned {len(products)} products.")

    if not products:
        return {"suggestions": []}

    # 2. Format data for Gemini
    history_context = []
    for p in products:
        days_since = 0
        if p.last_purchased_date:
            # FIX: Handle timezone offset issues (avoid -1 days)
            diff = datetime.utcnow() - p.last_purchased_date
            days_since = max(0, diff.days)

        history_context.append({
            "name": p.name,
            "category": p.category or "General", # Fallback category
            "days_ago": days_since, # Renamed for clarity
            "frequency": p.average_days_between_purchases,
            "count": p.purchase_count,
            "price": p.typical_price
        })

    # 3. Call Gemini
    try:
        gemini = GeminiService()
        print(f"🤖 [DEBUG] Using Model: {gemini.suggestion_model.model_name}")

        suggestions = await gemini.generate_suggestions(history_context)

        print(f"✅ [DEBUG] Gemini returned {len(suggestions)} suggestions.")
        return {"suggestions": suggestions}

    except Exception as e:
        print(f"❌ [DEBUG] GEMINI ERROR: {str(e)}")
        return {"suggestions": []}