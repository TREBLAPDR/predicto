from sqlalchemy import Column, String, Float, Integer, DateTime, Text, Boolean, ForeignKey, Index
from sqlalchemy.sql import func
from datetime import datetime
from .connection import Base

class Product(Base):
    __tablename__ = "products"

    id = Column(String, primary_key=True)
    name = Column(String(200), nullable=False, index=True)
    category = Column(String(50), nullable=False, index=True)
    typical_price = Column(Float, nullable=True)
    last_purchased_date = Column(DateTime, nullable=True)
    purchase_count = Column(Integer, default=0)
    average_days_between_purchases = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # For search optimization
    __table_args__ = (
        Index('idx_name_category', 'name', 'category'),
        Index('idx_purchase_date', 'last_purchased_date'),
    )

class ProductAssociation(Base):
    __tablename__ = "product_associations"

    id = Column(Integer, primary_key=True, autoincrement=True)
    product_a_id = Column(String, ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    product_b_id = Column(String, ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    co_purchase_count = Column(Integer, default=1)
    confidence = Column(Float, default=0.5)  # 0-1 confidence score
    last_purchased_together = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        Index('idx_product_pair', 'product_a_id', 'product_b_id'),
    )

class PurchaseHistory(Base):
    __tablename__ = "purchase_history"

    id = Column(Integer, primary_key=True, autoincrement=True)
    product_id = Column(String, ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    purchase_date = Column(DateTime, nullable=False, index=True)
    price = Column(Float, nullable=True)
    quantity = Column(Float, default=1.0)
    store_name = Column(String(200), nullable=True)

    __table_args__ = (
        Index('idx_product_date', 'product_id', 'purchase_date'),
    )