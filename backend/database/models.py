from sqlalchemy import Column, String, Float, DateTime, Integer, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid

# Import Base from connection (This now works!)
from database.connection import Base

class ShoppingList(Base):
    __tablename__ = "shopping_lists"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, nullable=False)
    store_name = Column(String, nullable=True)
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
    is_purchased = Column(Integer, default=0) # SQLite/PG boolean handling

    # Relationships
    shopping_list = relationship("ShoppingList", back_populates="items")

# NEW: Product Learning Table
class Product(Base):
    __tablename__ = "products"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, index=True)
    category = Column(String)
    typical_price = Column(Float, nullable=True)
    purchase_count = Column(Integer, default=1)
    last_purchased_date = Column(DateTime, default=datetime.utcnow)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)