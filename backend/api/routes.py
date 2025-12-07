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

# In-memory storage for demo
shared_lists_db = {}

@router.post("/process-advanced", response_model=ProcessReceiptResponse)
async def process_receipt_advanced(request: ProcessReceiptRequest):
    """
    Advanced receipt processing endpoint
    """
    start_time = time.time()
    last_error = None

    try:
        # Validate input
        if not request.imageBase64 and not request.ocrText:
            raise HTTPException(
                status_code=400,
                detail="Either imageBase64 or ocrText must be provided"
            )

        # Parsing Logic
        if request.useGemini and settings.is_gemini_configured:
            try:
                gemini_service = GeminiService()
                # Use retry method to be robust
                parsed_receipt = await gemini_service.parse_receipt_with_retry(
                    image_base64=request.imageBase64,
                    ocr_text=request.ocrText,
                    ocr_blocks=request.ocrBlocks
                )
                method = "gemini"
            except Exception as e:
                # Capture the actual error from Gemini
                print(f"Gemini parsing failed: {e}")
                last_error = str(e)
                parsed_receipt = _basic_parse(request.ocrText or "")
                method = "basic_fallback"
        else:
            # Gemini not configured or disabled by user
            if request.useGemini and not settings.is_gemini_configured:
                last_error = "Gemini API Key not configured in backend"

            parsed_receipt = _basic_parse(request.ocrText or "")
            method = "basic" if not request.useGemini else "gemini_not_configured"

        processing_time = int((time.time() - start_time) * 1000)

        # Return success=True but include the error message so UI can warn user
        return ProcessReceiptResponse(
            success=True,
            receipt=parsed_receipt,
            error=f"AI Failed: {last_error}" if last_error else None,
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
    Improved basic parsing fallback to handle cases where AI fails
    """
    import re

    lines = ocr_text.split('\n')
    items = []
    store_name = None
    total = None

    # 1. Improved Store Name Logic: Skip common receipt headers
    # This fixes the "CASHIER: KEN" or "OWNED BY" issue
    skip_headers = [
        'owned by', 'tax invoice', 'cash receipt', 'copy',
        'duplicate', 'merchant', 'terminal', 'cashier',
        'served by', 'gst no', 'vat reg', 'date:', 'time:',
        'welcome', 'thank you', 'ph:', 'tel:'
    ]

    for line in lines[:10]: # Check first 10 lines
        clean_line = line.strip()
        lower_line = clean_line.lower()

        # Must be longer than 3 chars, no digits, and not in skip list
        if (len(clean_line) > 3 and
            not re.search(r'\d', clean_line) and
            not any(h in lower_line for h in skip_headers)):
            store_name = clean_line
            break

    # 2. Extract Items
    price_pattern = re.compile(r'(\d+\.\d{2})')
    for line in lines:
        prices = price_pattern.findall(line)
        if prices and len(line.strip()) > 5:
            # Remove price from line to get item name
            item_text = re.sub(r'\d+\.\d{2}', '', line).strip()

            # Filter out lines that look like totals/tax
            bad_keywords = ['total', 'tax', 'subtotal', 'change', 'cash', 'card', 'visa', 'mastercard', 'amount']
            if (item_text and
                len(item_text) > 2 and
                not any(kw in item_text.lower() for kw in bad_keywords)):

                items.append(ReceiptItem(
                    name=item_text[:50],
                    price=float(prices[0]),
                    qty=1.0,
                    confidence=0.4
                ))

    # 3. Find Total
    for line in lines:
        if 'total' in line.lower() and 'sub' not in line.lower():
            prices = price_pattern.findall(line)
            if prices:
                total = float(prices[-1])
                break

    return ParsedReceipt(
        storeName=store_name,
        date=None,
        items=items[:20],
        total=total,
        parsingConfidence=0.3
    )

@router.post("/upload-image")
async def upload_image(file: UploadFile = File(...)):
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

@router.post("/share/create", response_model=ShareLinkResponse)
async def create_share_link(request: CreateShareRequest):
    import secrets
    try:
        share_id = secrets.token_urlsafe(8).upper()[:8]
        created_at = datetime.now()
        expires_at = created_at + timedelta(days=request.daysValid)

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
    try:
        share_id = share_id.upper().strip()
        if share_id not in shared_lists_db:
            raise HTTPException(404, "Share link not found")

        shared_data = shared_lists_db[share_id]
        expires_at = datetime.fromisoformat(shared_data["expiresAt"])
        if datetime.now() > expires_at:
            return AccessSharedListResponse(success=False, expired=True, error="Link expired")

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
        }
        return AccessSharedListResponse(success=True, shareInfo=share_info, list=list_data)
    except HTTPException:
        raise
    except Exception as e:
        return AccessSharedListResponse(success=False, error=str(e))

@router.delete("/share/{share_id}")
async def delete_share_link(share_id: str):
    share_id = share_id.upper().strip()
    if share_id in shared_lists_db:
        del shared_lists_db[share_id]
        return {"success": True}
    raise HTTPException(404, "Not found")

@router.get("/gemini-status")
async def gemini_status():
    return {
        "configured": settings.is_gemini_configured,
        "model": settings.GEMINI_MODEL,
        "message": "Gemini ready" if settings.is_gemini_configured else "API key missing"
    }