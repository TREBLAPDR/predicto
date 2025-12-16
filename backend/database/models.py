from sqlalchemy import Column, String, Float, DateTime, Integer, ForeignKey, Boolean
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid

# Import Base from connection to avoid circular import
from database.connection import Base

# ==================== SHOPPING LIST MODELS ====================

class ShoppingList(Base):
    __tablename__ = "shopping_lists"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, nullable=False)
    store_name = Column(String, nullable=True)
    # New columns to match your Flutter app
    status = Column(String, default="active")
    is_completed = Column(Boolean, default=False)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    items = relationship("ShoppingItem", back_populates="shopping_list", cascade="all, delete-orphan")

class ShoppingItem(Base):
    __tablename__ = "shopping_items"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    list_id = Column(String, ForeignKey("shopping_lists.id"), nullable=False)
    name = Column(String, nullable=False)
    qty = Column(Float, default=1.0)
    price = Column(Float, nullable=True)
    category = Column(String, default="Other")
    is_purchased = Column(Integer, default=0) # 0=False, 1=True
    notes = Column(String, nullable=True)     # Added missing column

    # Relationships
    shopping_list = relationship("ShoppingList", back_populates="items")

# ==================== PRODUCT LEARNING MODELS ====================

class Product(Base):
    __tablename__ = "products"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, index=True)
    category = Column(String)
    typical_price = Column(Float, nullable=True)
    purchase_count = Column(Integer, default=1)
    last_purchased_date = Column(DateTime, default=datetime.utcnow)

    # This was the missing column causing your 500 error
    average_days_between_purchases = Column(Float, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    purchase_history = relationship("PurchaseHistory", back_populates="product", cascade="all, delete-orphan")

class PurchaseHistory(Base):
    __tablename__ = "purchase_history"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    product_id = Column(String, ForeignKey("products.id"))
    purchase_date = Column(DateTime, default=datetime.utcnow)
    price = Column(Float, nullable=True)
    quantity = Column(Float, default=1.0)
    store_name = Column(String, nullable=True)

    # Relationships
    product = relationship("Product", back_populates="purchase_history")

class ProductAssociation(Base):
    __tablename__ = "product_associations"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    product_a_id = Column(String, ForeignKey("products.id"))
    product_b_id = Column(String, ForeignKey("products.id"))
    co_purchase_count = Column(Integer, default=1)
    confidence_score = Column(Float, default=0.0)
    last_updated = Column(DateTime, default=datetime.utcnow)