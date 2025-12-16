from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from datetime import datetime

from database.connection import get_session
from database import crud
from models.schemas import (
    ProductCreate,
    ProductUpdate,
    ProductResponse,
    ProductSearchResponse,
    PurchaseRecordRequest,
    AssociatedProductResponse,
    PredictionResponse,
)

router = APIRouter()

@router.post("/products", response_model=ProductResponse)
async def create_product(
    product: ProductCreate,
    session: AsyncSession = Depends(get_session),
):
    """Create a new product"""
    existing = await crud.get_product_by_name(session, product.name)
    if existing:
        raise HTTPException(400, "Product already exists")

    db_product = await crud.create_product(
        session,
        name=product.name,
        category=product.category,
        typical_price=product.typical_price,
    )
    return db_product

@router.get("/products", response_model=ProductSearchResponse)
async def get_products(
    category: Optional[str] = None,
    search: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
    session: AsyncSession = Depends(get_session),
):
    """Get all products with filtering"""
    products, total = await crud.get_products(
        session,
        category=category,
        search=search,
        limit=limit,
        offset=offset,
    )
    return {"products": products, "total": total}

@router.get("/products/{product_id}", response_model=ProductResponse)
async def get_product(
    product_id: str,
    session: AsyncSession = Depends(get_session),
):
    """Get single product"""
    product = await crud.get_product(session, product_id)
    if not product:
        raise HTTPException(404, "Product not found")
    return product

@router.put("/products/{product_id}", response_model=ProductResponse)
async def update_product(
    product_id: str,
    product: ProductUpdate,
    session: AsyncSession = Depends(get_session),
):
    """Update product"""
    db_product = await crud.update_product(
        session,
        product_id,
        name=product.name,
        category=product.category,
        typical_price=product.typical_price,
    )
    if not db_product:
        raise HTTPException(404, "Product not found")
    return db_product

@router.delete("/products/{product_id}")
async def delete_product(
    product_id: str,
    session: AsyncSession = Depends(get_session),
):
    """Delete product"""
    success = await crud.delete_product(session, product_id)
    if not success:
        raise HTTPException(404, "Product not found")
    return {"success": True}

# ==================== INTELLIGENT PURCHASE RECORDING ====================

@router.post("/products/purchase")
async def record_purchase(
    purchase: PurchaseRecordRequest,
    session: AsyncSession = Depends(get_session),
):
    """Record a product purchase with auto-creation logic"""

    final_product_id = purchase.product_id

    # 1. HANDLE 'UNKNOWN' ID CASE
    # If frontend sends 'unknown', we must find or create the product by name
    if not final_product_id or final_product_id.lower() == 'unknown':
        if not purchase.name:
            raise HTTPException(400, "Product name is required when product_id is unknown")

        # Try to find existing product by name
        existing_product = await crud.get_product_by_name(session, purchase.name)

        if existing_product:
            final_product_id = existing_product.id
        else:
            # Create new product on the fly
            new_product = await crud.create_product(
                session,
                name=purchase.name,
                category="Uncategorized", # Default category
                typical_price=purchase.price
            )
            final_product_id = new_product.id

    # 2. Record the purchase using the REAL ID
    purchase_date = purchase.purchase_date or datetime.utcnow()

    try:
        history = await crud.record_purchase(
            session,
            product_id=final_product_id,
            purchase_date=purchase_date,
            price=purchase.price,
            quantity=purchase.quantity,
            store_name=purchase.store_name,
        )
        return {"success": True, "id": history.id}

    except Exception as e:
        print(f"Error recording purchase: {e}")
        raise HTTPException(500, f"Database error: {str(e)}")

@router.get("/products/{product_id}/associations", response_model=List[AssociatedProductResponse])
async def get_product_associations(
    product_id: str,
    min_confidence: float = 0.3,
    session: AsyncSession = Depends(get_session),
):
    """Get products frequently bought with this product"""
    associations = await crud.get_associated_products(
        session,
        product_id,
        min_confidence=min_confidence,
    )
    return associations

@router.get("/products/predictions/needed", response_model=List[PredictionResponse])
async def get_predicted_products(
    days_ahead: int = 7,
    min_confidence: float = 0.5,
    session: AsyncSession = Depends(get_session),
):
    """Get products predicted to be needed soon"""
    predictions = await crud.predict_needed_products(
        session,
        days_ahead=days_ahead,
        min_confidence=min_confidence,
    )
    return predictions