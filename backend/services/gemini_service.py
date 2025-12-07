import google.generativeai as genai
from typing import Optional, Dict, Any
import json
import re
from PIL import Image
from io import BytesIO
import base64

from models.schemas import ParsedReceipt, ReceiptItem
from config import settings

class GeminiService:
    def __init__(self):
        if not settings.is_gemini_configured:
            raise ValueError("Gemini API key not configured. Please set GEMINI_API_KEY in .env")

        genai.configure(api_key=settings.GEMINI_API_KEY)
        self.model = genai.GenerativeModel(settings.GEMINI_MODEL)

    async def parse_receipt(
        self,
        image_base64: Optional[str] = None,
        ocr_text: Optional[str] = None,
        ocr_blocks: Optional[list] = None
    ) -> ParsedReceipt:
        """
        Parse receipt using Gemini Pro Vision API

        Args:
            image_base64: Base64 encoded receipt image (preferred)
            ocr_text: Fallback OCR text if image not available
            ocr_blocks: OCR blocks with bounding boxes (optional context)

        Returns:
            ParsedReceipt object with structured data
        """

        # Build the prompt
        prompt = self._build_prompt(ocr_text, ocr_blocks)

        try:
            # If image is provided, use vision capabilities
            if image_base64:
                image_bytes = base64.b64decode(image_base64)
                image = Image.open(BytesIO(image_bytes))

                # Generate content with image + text prompt
                response = self.model.generate_content(
                    [prompt, image],
                    generation_config=genai.types.GenerationConfig(
                        temperature=settings.GEMINI_TEMPERATURE,
                        max_output_tokens=settings.GEMINI_MAX_TOKENS,
                    )
                )
            else:
                # Text-only mode (fallback)
                response = self.model.generate_content(
                    prompt,
                    generation_config=genai.types.GenerationConfig(
                        temperature=settings.GEMINI_TEMPERATURE,
                        max_output_tokens=settings.GEMINI_MAX_TOKENS,
                    )
                )

            # Extract and parse JSON from response
            parsed_data = self._extract_json(response.text)

            # Validate and convert to ParsedReceipt
            receipt = self._validate_and_build_receipt(parsed_data)

            return receipt

        except Exception as e:
            raise Exception(f"Gemini parsing failed: {str(e)}")

    def _build_prompt(self, ocr_text: Optional[str], ocr_blocks: Optional[list]) -> str:
        """
        Build the prompt for Gemini with strict JSON output requirements
        """

        prompt = """You are an expert receipt parser. Analyze this receipt image or OCR text and extract structured information.

**CRITICAL: You must respond with ONLY valid JSON. No markdown, no explanation, no preamble.**

Your response must be a single JSON object with this exact structure:
{
  "storeName": "string or null",
  "date": "YYYY-MM-DD or null",
  "items": [
    {
      "name": "item name",
      "price": 12.99,
      "qty": 1.0,
      "confidence": 0.95
    }
  ],
  "subtotal": 45.67,
  "tax": 3.65,
  "total": 49.32,
  "parsingConfidence": 0.90
}

**Parsing Rules:**
1. Extract the store/merchant name from the top of the receipt
2. Find the date in format YYYY-MM-DD (convert if needed)
3. For each item line, extract:
   - name: The product/item description
   - price: The unit or total price for that item
   - qty: Quantity purchased (default to 1.0 if not shown)
   - confidence: Your confidence in this extraction (0.0-1.0)
4. Identify subtotal (before tax), tax amount, and final total
5. Set parsingConfidence based on receipt quality and extraction certainty
6. If a field cannot be determined, use null (not empty string)
7. Prices must be numbers (float), not strings
8. Exclude non-product lines (payment methods, change, thank you messages)

**Price Alignment Rules:**
- Match item names with their corresponding prices using spatial position
- Prices are typically right-aligned on receipts
- If multiple numbers appear on a line, the rightmost is usually the price
- Ignore department codes, item codes, and tax indicators (T, F markers)

"""

        # Add OCR context if available
        if ocr_text:
            prompt += f"\n**OCR Extracted Text:**\n```\n{ocr_text[:2000]}\n```\n"

        if ocr_blocks:
            prompt += f"\n**Number of OCR blocks detected:** {len(ocr_blocks)}\n"

        prompt += "\n**Now output ONLY the JSON object, nothing else:**"

        return prompt

    def _extract_json(self, response_text: str) -> Dict[str, Any]:
        """
        Extract JSON from Gemini response, handling markdown code blocks
        """
        # Remove markdown code blocks if present
        text = response_text.strip()

        # Try to find JSON between ```json and ``` or ``` markers
        json_match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, re.DOTALL)
        if json_match:
            text = json_match.group(1)

        # Find the first { and last }
        start = text.find('{')
        end = text.rfind('}')

        if start == -1 or end == -1:
            raise ValueError("No JSON object found in response")

        json_str = text[start:end+1]

        try:
            return json.loads(json_str)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in response: {str(e)}\nResponse: {json_str[:500]}")

    def _validate_and_build_receipt(self, data: Dict[str, Any]) -> ParsedReceipt:
        """
        Validate parsed data and build ParsedReceipt object
        """
        # Build items list
        items = []
        for item_data in data.get('items', []):
            try:
                items.append(ReceiptItem(
                    name=str(item_data.get('name', 'Unknown')),
                    price=float(item_data['price']) if item_data.get('price') is not None else None,
                    qty=float(item_data.get('qty', 1.0)),
                    confidence=float(item_data.get('confidence', 0.8))
                ))
            except (KeyError, ValueError, TypeError):
                # Skip invalid items
                continue

        # Build receipt object
        return ParsedReceipt(
            storeName=data.get('storeName'),
            date=data.get('date'),
            items=items,
            subtotal=float(data['subtotal']) if data.get('subtotal') is not None else None,
            tax=float(data['tax']) if data.get('tax') is not None else None,
            total=float(data['total']) if data.get('total') is not None else None,
            parsingConfidence=float(data.get('parsingConfidence', 0.7))
        )

    def calculate_confidence(self, receipt: ParsedReceipt) -> float:
        """
        Calculate overall confidence score based on extracted data quality
        """
        confidence_factors = []

        # Store name found
        if receipt.storeName:
            confidence_factors.append(0.9)

        # Date found
        if receipt.date:
            confidence_factors.append(0.9)

        # Items extracted
        if receipt.items:
            avg_item_confidence = sum(item.confidence for item in receipt.items) / len(receipt.items)
            confidence_factors.append(avg_item_confidence)

        # Total matches sum of items (with tolerance)
        if receipt.total and receipt.items:
            items_sum = sum(item.price or 0 for item in receipt.items)
            if abs(receipt.total - items_sum) < 1.0:  # Within $1
                confidence_factors.append(0.95)
            else:
                confidence_factors.append(0.6)

        return sum(confidence_factors) / len(confidence_factors) if confidence_factors else 0.5