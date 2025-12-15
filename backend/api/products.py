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
    # Check if product already exists
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
    """Get all products or search"""
    if search:
        products = await crud.search_products(session, search, category, limit)
    else:
        products = await crud.get_all_products(session, category, limit, offset)

    return ProductSearchResponse(
        products=products,
        total=len(products),
    )

@router.get("/products/{product_id}", response_model=ProductResponse)
async def get_product(
    product_id: str,
    session: AsyncSession = Depends(get_session),
):
    """Get product by ID"""
    product = await crud.get_product(session, product_id)
    if not product:
        raise HTTPException(404, "Product not found")
    return product

@router.put("/products/{product_id}", response_model=ProductResponse)
async def update_product(
    product_id: str,
    product_update: ProductUpdate,
    session: AsyncSession = Depends(get_session),
):
    """Update product"""
    updates = product_update.dict(exclude_unset=True)
    if not updates:
        raise HTTPException(400, "No fields to update")

    product = await crud.update_product(session, product_id, **updates)
    if not product:
        raise HTTPException(404, "Product not found")

    return product

@router.delete("/products/{product_id}")
async def delete_product(
    product_id: str,
    session: AsyncSession = Depends(get_session),
):
    """Delete product"""
    success = await crud.delete_product(session, product_id)
    if not success:
        raise HTTPException(404, "Product not found")

    return {"success": True, "message": "Product deleted"}

@router.post("/products/purchase")
async def record_purchase(
    purchase: PurchaseRecordRequest,
    session: AsyncSession = Depends(get_session),
):
    """Record a product purchase"""
    purchase_date = purchase.purchase_date or datetime.utcnow()

    history = await crud.record_purchase(
        session,
        product_id=purchase.product_id,
        purchase_date=purchase_date,
        price=purchase.price,
        quantity=purchase.quantity,
        store_name=purchase.store_name,
    )

    return {"success": True, "id": history.id}

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