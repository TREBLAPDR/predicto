from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_, update, delete
from typing import List, Optional, Dict, Any
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

async def search_products(
    session: AsyncSession,
    query: str,
    category: Optional[str] = None,
    limit: int = 20,
) -> List[Product]:
    """Search products by name"""
    stmt = select(Product).where(
        Product.name.ilike(f"%{query}%")
    )

    if category:
        stmt = stmt.where(Product.category == category)

    stmt = stmt.order_by(Product.purchase_count.desc()).limit(limit)

    result = await session.execute(stmt)
    return result.scalars().all()

async def get_all_products(
    session: AsyncSession,
    category: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> List[Product]:
    """Get all products with optional category filter"""
    stmt = select(Product)

    if category:
        stmt = stmt.where(Product.category == category)

    stmt = stmt.order_by(Product.name).limit(limit).offset(offset)

    result = await session.execute(stmt)
    return result.scalars().all()

async def update_product(
    session: AsyncSession,
    product_id: str,
    **kwargs,
) -> Optional[Product]:
    """Update product fields"""
    kwargs['updated_at'] = datetime.utcnow()

    await session.execute(
        update(Product)
        .where(Product.id == product_id)
        .values(**kwargs)
    )
    await session.commit()

    return await get_product(session, product_id)

async def delete_product(session: AsyncSession, product_id: str) -> bool:
    """Delete a product"""
    result = await session.execute(
        delete(Product).where(Product.id == product_id)
    )
    await session.commit()
    return result.rowcount > 0

# ==================== PURCHASE HISTORY ====================

async def record_purchase(
    session: AsyncSession,
    product_id: str,
    purchase_date: datetime,
    price: Optional[float] = None,
    quantity: float = 1.0,
    store_name: Optional[str] = None,
) -> PurchaseHistory:
    """Record a purchase"""
    purchase = PurchaseHistory(
        product_id=product_id,
        purchase_date=purchase_date,
        price=price,
        quantity=quantity,
        store_name=store_name,
    )
    session.add(purchase)

    # Update product stats
    product = await get_product(session, product_id)
    if product:
        product.purchase_count += 1
        product.last_purchased_date = purchase_date

        # Update typical price (moving average)
        if price:
            if product.typical_price:
                product.typical_price = (product.typical_price * 0.7) + (price * 0.3)
            else:
                product.typical_price = price

        # Calculate average days between purchases
        history = await get_purchase_history(session, product_id, limit=10)
        if len(history) >= 2:
            intervals = []
            for i in range(1, len(history)):
                days = (history[i-1].purchase_date - history[i].purchase_date).days
                if days > 0:
                    intervals.append(days)

            if intervals:
                product.average_days_between_purchases = sum(intervals) / len(intervals)

    await session.commit()
    await session.refresh(purchase)
    return purchase

async def get_purchase_history(
    session: AsyncSession,
    product_id: str,
    limit: int = 50,
) -> List[PurchaseHistory]:
    """Get purchase history for a product"""
    result = await session.execute(
        select(PurchaseHistory)
        .where(PurchaseHistory.product_id == product_id)
        .order_by(PurchaseHistory.purchase_date.desc())
        .limit(limit)
    )
    return result.scalars().all()

# ==================== PRODUCT ASSOCIATIONS ====================

async def record_association(
    session: AsyncSession,
    product_a_id: str,
    product_b_id: str,
) -> ProductAssociation:
    """Record that two products were purchased together"""
    # Ensure consistent ordering (smaller ID first)
    if product_a_id > product_b_id:
        product_a_id, product_b_id = product_b_id, product_a_id

    # Check if association exists
    result = await session.execute(
        select(ProductAssociation).where(
            and_(
                ProductAssociation.product_a_id == product_a_id,
                ProductAssociation.product_b_id == product_b_id,
            )
        )
    )
    association = result.scalar_one_or_none()

    if association:
        # Increment count
        association.co_purchase_count += 1
        association.confidence = min(association.co_purchase_count / 10.0, 1.0)
        association.last_purchased_together = datetime.utcnow()
    else:
        # Create new association
        association = ProductAssociation(
            product_a_id=product_a_id,
            product_b_id=product_b_id,
            co_purchase_count=1,
            confidence=0.1,
            last_purchased_together=datetime.utcnow(),
        )
        session.add(association)

    await session.commit()
    await session.refresh(association)
    return association

async def get_associated_products(
    session: AsyncSession,
    product_id: str,
    min_confidence: float = 0.3,
    limit: int = 10,
) -> List[Dict[str, Any]]:
    """Get products frequently bought with this product"""
    result = await session.execute(
        select(ProductAssociation, Product)
        .join(
            Product,
            or_(
                Product.id == ProductAssociation.product_a_id,
                Product.id == ProductAssociation.product_b_id,
            )
        )
        .where(
            and_(
                or_(
                    ProductAssociation.product_a_id == product_id,
                    ProductAssociation.product_b_id == product_id,
                ),
                ProductAssociation.confidence >= min_confidence,
                Product.id != product_id,
            )
        )
        .order_by(ProductAssociation.confidence.desc())
        .limit(limit)
    )

    associations = []
    for assoc, product in result:
        associations.append({
            'product': product,
            'confidence': assoc.confidence,
            'co_purchase_count': assoc.co_purchase_count,
        })

    return associations

# ==================== PREDICTIONS ====================

async def predict_needed_products(
    session: AsyncSession,
    days_ahead: int = 7,
    min_confidence: float = 0.5,
) -> List[Dict[str, Any]]:
    """Predict products that might be needed soon based on purchase frequency"""
    today = datetime.utcnow()

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