from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_, update, delete
from typing import List, Optional, Dict, Any, Tuple
from datetime import datetime, timedelta
import uuid

from .models import Product, ProductAssociation, PurchaseHistory

# ==================== PRODUCTS ====================

async def create_product(
    session: AsyncSession,
    name: str,
    category: str,
    typical_price: Optional[float] = None,
) -> Product:
    """Create a new product"""
    product = Product(
        id=str(uuid.uuid4()),
        name=name,
        category=category,
        typical_price=typical_price,
        purchase_count=0,
    )
    session.add(product)
    await session.commit()
    await session.refresh(product)
    return product

async def get_product(session: AsyncSession, product_id: str) -> Optional[Product]:
    """Get product by ID"""
    result = await session.execute(
        select(Product).where(Product.id == product_id)
    )
    return result.scalar_one_or_none()

async def get_product_by_name(session: AsyncSession, name: str) -> Optional[Product]:
    """Get product by exact name (case-insensitive)"""
    result = await session.execute(
        select(Product).where(func.lower(Product.name) == name.lower())
    )
    return result.scalar_one_or_none()

# --- THIS WAS MISSING ---
async def get_products(
    session: AsyncSession,
    category: Optional[str] = None,
    search: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> Tuple[List[Product], int]:
    """Get list of products with filtering and pagination"""
    query = select(Product)

    if category:
        query = query.where(Product.category == category)

    if search:
        query = query.where(Product.name.ilike(f"%{search}%"))

    # Get total count
    count_query = select(func.count()).select_from(query.subquery())
    total = (await session.execute(count_query)).scalar_one()

    # Get items
    query = query.order_by(Product.name).limit(limit).offset(offset)
    result = await session.execute(query)

    return result.scalars().all(), total
# ------------------------

async def update_product(
    session: AsyncSession,
    product_id: str,
    name: Optional[str] = None,
    category: Optional[str] = None,
    typical_price: Optional[float] = None,
) -> Optional[Product]:
    """Update product details"""
    query = update(Product).where(Product.id == product_id)
    values = {}

    if name: values['name'] = name
    if category: values['category'] = category
    if typical_price is not None: values['typical_price'] = typical_price

    if not values:
        return await get_product(session, product_id)

    values['updated_at'] = datetime.utcnow()
    query = query.values(**values).execution_options(synchronize_session="fetch")

    await session.execute(query)
    await session.commit()

    return await get_product(session, product_id)

async def delete_product(session: AsyncSession, product_id: str) -> bool:
    """Delete a product"""
    result = await session.execute(
        delete(Product).where(Product.id == product_id)
    )
    await session.commit()
    return result.rowcount > 0

# ==================== PURCHASE HISTORY & LEARNING ====================

async def record_purchase(
    session: AsyncSession,
    product_id: str,
    purchase_date: datetime,
    price: Optional[float],
    quantity: float = 1.0,
    store_name: Optional[str] = None,
) -> PurchaseHistory:
    """Record a purchase and update product stats"""

    # 1. Create history entry
    history = PurchaseHistory(
        id=str(uuid.uuid4()),
        product_id=product_id,
        purchase_date=purchase_date,
        price=price,
        quantity=quantity,
        store_name=store_name,
    )
    session.add(history)

    # 2. Update Product Stats (Count, Last Purchased, Frequency)
    product = await get_product(session, product_id)
    if product:
        # Calculate new average days
        if product.last_purchased_date:
            days_diff = (purchase_date - product.last_purchased_date).days
            if days_diff > 0:
                current_avg = product.average_days_between_purchases or days_diff
                # Weighted average: 70% old, 30% new
                new_avg = (current_avg * 0.7) + (days_diff * 0.3)
                product.average_days_between_purchases = new_avg

        product.purchase_count += 1
        product.last_purchased_date = purchase_date
        if price:
            product.typical_price = price

    await session.commit()
    await session.refresh(history)
    return history

async def record_association(
    session: AsyncSession,
    product_a_id: str,
    product_b_id: str,
) -> None:
    """Record that two products were bought together"""
    if product_a_id == product_b_id:
        return

    # Sort IDs to ensure consistent storage (A < B)
    id1, id2 = sorted([product_a_id, product_b_id])

    result = await session.execute(
        select(ProductAssociation).where(
            and_(
                ProductAssociation.product_a_id == id1,
                ProductAssociation.product_b_id == id2
            )
        )
    )
    association = result.scalar_one_or_none()

    if association:
        association.co_purchase_count += 1
        association.last_updated = datetime.utcnow()
    else:
        association = ProductAssociation(
            id=str(uuid.uuid4()),
            product_a_id=id1,
            product_b_id=id2,
            co_purchase_count=1,
            confidence_score=0.1
        )
        session.add(association)

    await session.commit()

async def get_associated_products(
    session: AsyncSession,
    product_id: str,
    min_confidence: float = 0.3,
) -> List[Dict[str, Any]]:
    """Get products frequently bought with the given product"""

    # Find associations where product_id is either A or B
    result = await session.execute(
        select(ProductAssociation).where(
            or_(
                ProductAssociation.product_a_id == product_id,
                ProductAssociation.product_b_id == product_id
            )
        ).order_by(ProductAssociation.co_purchase_count.desc())
    )
    associations = result.scalars().all()

    related_products = []
    for assoc in associations:
        # Determine the "other" product ID
        other_id = assoc.product_b_id if assoc.product_a_id == product_id else assoc.product_a_id

        other_product = await get_product(session, other_id)
        if other_product:
            # Simple confidence calc
            confidence = min(assoc.co_purchase_count / 10.0, 0.95)

            if confidence >= min_confidence:
                related_products.append({
                    'product': other_product,
                    'confidence': confidence,
                    'co_purchase_count': assoc.co_purchase_count
                })

    return related_products

# ==================== PREDICTIONS ====================

async def predict_needed_products(
    session: AsyncSession,
    days_ahead: int = 7,
    min_confidence: float = 0.5,
) -> List[Dict[str, Any]]:
    """Predict products that might be needed soon based on purchase frequency"""
    today = datetime.utcnow()

    # Find products that have purchase history
    result = await session.execute(
        select(Product).where(
            and_(
                Product.average_days_between_purchases.isnot(None),
                Product.last_purchased_date.isnot(None),
            )
        )
    )
    products = result.scalars().all()

    predictions = []
    for product in products:
        days_since_purchase = (today - product.last_purchased_date).days
        expected_days = product.average_days_between_purchases

        # Predict if we're close to the usual repurchase time
        if expected_days and days_since_purchase >= (expected_days * 0.8):
            confidence = min((days_since_purchase / expected_days), 1.0)

            if confidence >= min_confidence:
                predictions.append({
                    'product': product,
                    'confidence': confidence,
                    'days_since_purchase': days_since_purchase,
                    'expected_days': expected_days,
                })

    # Sort by confidence
    predictions.sort(key=lambda x: x['confidence'], reverse=True)
    return predictions