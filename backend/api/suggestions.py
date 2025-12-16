from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timezone
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
        print("⚠️ [DEBUG] No products found in database")
        return {"suggestions": []}

    # 2. Format data for Gemini with FIXED date calculations
    history_context = []
    now = datetime.now(timezone.utc)  # Use timezone-aware datetime

    for p in products:
        # Handle timezone-aware vs naive datetime
        if p.last_purchased_date:
            # Make last_purchased_date timezone-aware if it isn't
            if p.last_purchased_date.tzinfo is None:
                last_date = p.last_purchased_date.replace(tzinfo=timezone.utc)
            else:
                last_date = p.last_purchased_date

            # Calculate days difference
            diff = now - last_date
            days_since = max(0, diff.days)  # Ensure non-negative
        else:
            days_since = 999  # Default for items never purchased

        history_context.append({
            "name": p.name,
            "category": p.category or "General",
            "days_ago": days_since,
            "frequency": p.average_days_between_purchases,
            "count": p.purchase_count,
            "price": p.typical_price
        })

    print(f"📊 [DEBUG] Sample history item: {history_context[0] if history_context else 'None'}")

    # 3. Call Gemini with better error handling
    try:
        gemini = GeminiService()
        print(f"🤖 [DEBUG] Using Model: {gemini.suggestion_model.model_name}")

        suggestions = await gemini.generate_suggestions(history_context)

        print(f"✅ [DEBUG] Gemini returned {len(suggestions)} suggestions.")

        if not suggestions:
            print("⚠️ [DEBUG] Gemini returned empty suggestions array")
            print("📋 [DEBUG] This might be a prompt issue or API limitation")

        return {"suggestions": suggestions}

    except ValueError as e:
        # Gemini not configured
        print(f"⚠️ [DEBUG] Configuration error: {str(e)}")
        return {
            "suggestions": [],
            "error": "Gemini API not configured"
        }
    except Exception as e:
        print(f"❌ [DEBUG] GEMINI ERROR: {str(e)}")
        import traceback
        print(f"📋 [DEBUG] Stack trace:\n{traceback.format_exc()}")
        return {
            "suggestions": [],
            "error": str(e)
        }