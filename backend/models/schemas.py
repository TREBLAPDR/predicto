from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime, timedelta

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