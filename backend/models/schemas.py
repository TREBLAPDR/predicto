from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime, timedelta

# ==================== RECEIPT & PARSING SCHEMAS ====================

class ReceiptItem(BaseModel):
    name: str
    price: Optional[float] = None
    qty: Optional[float] = None
    confidence: float = Field(ge=0.0, le=1.0, default=0.0)

class ParsedReceipt(BaseModel):
    storeName: Optional[str] = None
    date: Optional[str] = None  # Format: YYYY-MM-DD
    items: List[ReceiptItem] = []
    subtotal: Optional[float] = None
    tax: Optional[float] = None
    total: Optional[float] = None
    parsingConfidence: float = Field(ge=0.0, le=1.0, default=0.0)

class OCRTextBlock(BaseModel):
    text: str
    boundingBox: dict
    confidence: float

class ProcessReceiptRequest(BaseModel):
    """Request format for advanced receipt processing"""
    imageBase64: Optional[str] = None  # Base64 encoded image
    ocrText: Optional[str] = None  # Raw OCR text
    ocrBlocks: Optional[List[OCRTextBlock]] = None  # OCR blocks with positions
    useGemini: bool = True  # Whether to use Gemini or basic parsing

class ProcessReceiptResponse(BaseModel):
    success: bool
    receipt: Optional[ParsedReceipt] = None
    error: Optional[str] = None
    processingTimeMs: int
    method: str  # "gemini" or "basic"

# ==================== SHARING SCHEMAS ====================

class CreateShareRequest(BaseModel):
    listId: str
    listName: str
    items: List[dict]
    permission: str = "edit"  # view, edit, admin
    daysValid: int = 7

class ShareInfo(BaseModel):
    shareId: str
    listId: str
    listName: str
    ownerName: str = "Someone"
    createdAt: str
    expiresAt: str
    itemCount: int
    permission: str

class ShareLinkResponse(BaseModel):
    success: bool
    shareInfo: Optional[ShareInfo] = None
    error: Optional[str] = None

class AccessSharedListResponse(BaseModel):
    success: bool
    expired: bool = False
    shareInfo: Optional[ShareInfo] = None
    list: Optional[dict] = None
    error: Optional[str] = None

# ==================== PRODUCT SCHEMAS ====================

class ProductBase(BaseModel):
    name: str
    category: str
    typical_price: Optional[float] = None

class ProductCreate(ProductBase):
    pass

class ProductUpdate(BaseModel):
    name: Optional[str] = None
    category: Optional[str] = None
    typical_price: Optional[float] = None

class ProductResponse(ProductBase):
    id: str
    purchase_count: int
    last_purchased_date: Optional[datetime] = None
    average_days_between_purchases: Optional[float] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class ProductSearchResponse(BaseModel):
    products: List[ProductResponse]
    total: int

class PurchaseRecordRequest(BaseModel):
    product_id: str
    purchase_date: Optional[datetime] = None
    price: Optional[float] = None
    quantity: float = 1.0
    store_name: Optional[str] = None

class AssociatedProductResponse(BaseModel):
    product: ProductResponse
    confidence: float
    co_purchase_count: int

class PredictionResponse(BaseModel):
    product: ProductResponse
    confidence: float
    days_since_purchase: int
    expected_days: float