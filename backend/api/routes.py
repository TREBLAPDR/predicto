from fastapi import APIRouter, HTTPException, UploadFile, File
from fastapi.responses import JSONResponse
from typing import Optional
import time
import base64
from io import BytesIO
from PIL import Image
from datetime import datetime, timedelta
from models.schemas import (
    ProcessReceiptRequest,
    ProcessReceiptResponse,
    ParsedReceipt,
    ReceiptItem,
    CreateShareRequest,
    ShareInfo,
    ShareLinkResponse,
    AccessSharedListResponse,
)
from services.gemini_service import GeminiService
from config import settings

router = APIRouter()

@router.post("/process-advanced", response_model=ProcessReceiptResponse)
async def process_receipt_advanced(request: ProcessReceiptRequest):
    """
    Advanced receipt processing endpoint
    Accepts: preprocessed image (base64) and/or OCR text + blocks
    Returns: Structured receipt data (JSON)
        PRIVACY NOTE: When useGemini=true, image data is sent to Google's Gemini API.
    This may include store names, item details, and receipt content.
    """
    start_time = time.time()

    try:
        # Validate input
        if not request.imageBase64 and not request.ocrText:
            raise HTTPException(
                status_code=400,
                detail="Either imageBase64 or ocrText must be provided"
            )

        # Decode and validate image if provided
        image = None
        if request.imageBase64:
            try:
                image_bytes = base64.b64decode(request.imageBase64)
                image = Image.open(BytesIO(image_bytes))
                if image.size[0] < 100 or image.size[1] < 100:
                    raise HTTPException(400, "Image too small (min 100x100)")
                if image.size[0] > 4096 or image.size[1] > 4096:
                    raise HTTPException(400, "Image too large (max 4096x4096)")
            except Exception as e:
                raise HTTPException(400, f"Invalid image data: {str(e)}")

        # Choose parsing method
        if request.useGemini and settings.is_gemini_configured:
            try:
                gemini_service = GeminiService()
                parsed_receipt = await gemini_service.parse_receipt(
                    image_base64=request.imageBase64,
                    ocr_text=request.ocrText,
                    ocr_blocks=request.ocrBlocks
                )
                method = "gemini"
            except Exception as e:
                # Fallback to basic parsing if Gemini fails
                print(f"Gemini parsing failed: {e}, falling back to basic")
                parsed_receipt = _basic_parse(request.ocrText or "")
                method = "basic_fallback"
        else:
            # Use basic parsing
            parsed_receipt = _basic_parse(request.ocrText or "")
            method = "basic" if not request.useGemini else "gemini_not_configured"

        processing_time = int((time.time() - start_time) * 1000)

        return ProcessReceiptResponse(
            success=True,
            receipt=parsed_receipt,
            error=None,
            processingTimeMs=processing_time,
            method=method
        )

    except HTTPException:
        raise
    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        return ProcessReceiptResponse(
            success=False,
            receipt=None,
            error=str(e),
            processingTimeMs=processing_time,
            method="error"
        )

def _basic_parse(ocr_text: str) -> ParsedReceipt:
    """
    Basic parsing fallback (without AI)
    Simple pattern matching for demo purposes
    """
    import re

    lines = ocr_text.split('\n')
    items = []
    store_name = None
    total = None

    # Try to find store name (usually first few lines)
    for line in lines[:5]:
        if len(line.strip()) > 3 and not re.search(r'\d', line):
            store_name = line.strip()
            break

    # Find items with prices
    price_pattern = re.compile(r'(\d+\.\d{2})')
    for line in lines:
        prices = price_pattern.findall(line)
        if prices and len(line.strip()) > 5:
            # Extract item name (text before price)
            item_text = re.sub(r'\d+\.\d{2}', '', line).strip()
            if item_text and not any(kw in item_text.lower() for kw in ['total', 'tax', 'subtotal']):
                items.append(ReceiptItem(
                    name=item_text[:50],
                    price=float(prices[0]),
                    qty=1.0,
                    confidence=0.6
                ))

    # Find total
    for line in lines:
        if 'total' in line.lower():
            prices = price_pattern.findall(line)
            if prices:
                total = float(prices[-1])
                break

    return ParsedReceipt(
        storeName=store_name,
        date=None,
        items=items[:20],
        subtotal=None,
        tax=None,
        total=total,
        parsingConfidence=0.5
    )

@router.post("/upload-image")
async def upload_image(file: UploadFile = File(...)):
    """
    Alternative endpoint: upload image directly as multipart/form-data
    """
    try:
        contents = await file.read()
        image_base64 = base64.b64encode(contents).decode('utf-8')

        return JSONResponse({
            "success": True,
            "message": "Image received",
            "fileSize": len(contents),
            "filename": file.filename,
            "imageBase64": image_base64[:100] + "..."
        })
    except Exception as e:
        raise HTTPException(500, f"Upload failed: {str(e)}")

# In-memory storage for demo (use database in production)
shared_lists_db = {}

@router.post("/share/create", response_model=ShareLinkResponse)
async def create_share_link(request: CreateShareRequest):
    """Create a shareable link for a shopping list"""
    import secrets

    try:
        # Generate unique share ID
        share_id = secrets.token_urlsafe(8).upper()[:8]

        # Calculate expiration
        created_at = datetime.now()
        expires_at = created_at + timedelta(days=request.daysValid)

        # Store shared list
        shared_lists_db[share_id] = {
            "listId": request.listId,
            "listName": request.listName,
            "items": request.items,
            "permission": request.permission,
            "createdAt": created_at.isoformat(),
            "expiresAt": expires_at.isoformat(),
        }

        share_info = ShareInfo(
            shareId=share_id,
            listId=request.listId,
            listName=request.listName,
            createdAt=created_at.isoformat(),
            expiresAt=expires_at.isoformat(),
            itemCount=len(request.items),
            permission=request.permission,
        )

        return ShareLinkResponse(success=True, shareInfo=share_info)

    except Exception as e:
        return ShareLinkResponse(success=False, error=str(e))

@router.get("/share/{share_id}", response_model=AccessSharedListResponse)
async def access_shared_list(share_id: str):
    """Access a shared list via share ID"""
    try:
        share_id = share_id.upper().strip()

        if share_id not in shared_lists_db:
            raise HTTPException(404, "Share link not found")

        shared_data = shared_lists_db[share_id]

        # Check if expired
        expires_at = datetime.fromisoformat(shared_data["expiresAt"])
        is_expired = datetime.now() > expires_at

        if is_expired:
            return AccessSharedListResponse(
                success=False,
                expired=True,
                error="This share link has expired"
            )

        share_info = ShareInfo(
            shareId=share_id,
            listId=shared_data["listId"],
            listName=shared_data["listName"],
            createdAt=shared_data["createdAt"],
            expiresAt=shared_data["expiresAt"],
            itemCount=len(shared_data["items"]),
            permission=shared_data["permission"],
        )

        list_data = {
            "listName": shared_data["listName"],
            "items": shared_data["items"],
            "createdAt": shared_data["createdAt"],
            "storeName": None,
        }

        return AccessSharedListResponse(
            success=True,
            expired=False,
            shareInfo=share_info,
            list=list_data,
        )

    except HTTPException:
        raise
    except Exception as e:
        return AccessSharedListResponse(success=False, error=str(e))

@router.delete("/share/{share_id}")
async def delete_share_link(share_id: str):
    """Delete a share link"""
    share_id = share_id.upper().strip()

    if share_id in shared_lists_db:
        del shared_lists_db[share_id]
        return {"success": True, "message": "Share link deleted"}

    raise HTTPException(404, "Share link not found")

@router.get("/gemini-status")
async def gemini_status():
    """Check if Gemini API is configured"""
    return {
        "configured": settings.is_gemini_configured,
        "model": settings.GEMINI_MODEL if settings.is_gemini_configured else None,
        "message": "Gemini ready" if settings.is_gemini_configured else "API key not configured"
    }