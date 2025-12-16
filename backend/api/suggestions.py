from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime

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
    Get AI-powered suggestions based on purchase history using Gemini Model 2
    """
    # 1. Fetch relevant product history
    # We prioritize items bought recently or frequently
    result = await session.execute(
        select(Product)
        .where(Product.purchase_count > 0)
        .order_by(Product.last_purchased_date.desc())
        .limit(limit)
    )
    products = result.scalars().all()

    if not products:
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

    # 3. Call Gemini Model 2
    try:
        gemini = GeminiService()
        suggestions = await gemini.generate_suggestions(history_context)
        return {"suggestions": suggestions}
    except Exception as e:
        print(f"Error generating suggestions: {e}")
        # Return empty list on error instead of crashing UI
        return {"suggestions": [], "error": str(e)}