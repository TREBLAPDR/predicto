from fastapi import APIRouter, HTTPException, UploadFile, File
from fastapi.responses import JSONResponse
from typing import Optional
import time
import base64
from io import BytesIO
from PIL import Image
from models.schemas import (
    ProcessReceiptRequest,
    ProcessReceiptResponse,
    ParsedReceipt,
    ReceiptItem
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

@router.get("/gemini-status")
async def gemini_status():
    """Check if Gemini API is configured"""
    return {
        "configured": settings.is_gemini_configured,
        "model": settings.GEMINI_MODEL if settings.is_gemini_configured else None,
        "message": "Gemini ready" if settings.is_gemini_configured else "API key not configured"
    }