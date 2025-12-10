import google.generativeai as genai
from typing import Optional, Dict, Any
import json
import re
from PIL import Image
from io import BytesIO
import base64
import asyncio
from functools import partial

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
            # Run Gemini call in thread pool since it's synchronous
            loop = asyncio.get_event_loop()

            if image_base64:
                image_bytes = base64.b64decode(image_base64)
                image = Image.open(BytesIO(image_bytes))

                # Run synchronous Gemini call in executor
                response = await loop.run_in_executor(
                    None,
                    partial(
                        self.model.generate_content,
                        [prompt, image],
                        generation_config=genai.types.GenerationConfig(
                            temperature=settings.GEMINI_TEMPERATURE,
                            max_output_tokens=settings.GEMINI_MAX_TOKENS,
                        )
                    )
                )
            else:
                # Text-only mode (fallback)
                response = await loop.run_in_executor(
                    None,
                    partial(
                        self.model.generate_content,
                        prompt,
                        generation_config=genai.types.GenerationConfig(
                            temperature=settings.GEMINI_TEMPERATURE,
                            max_output_tokens=settings.GEMINI_MAX_TOKENS,
                        )
                    )
                )

            # Extract and parse JSON from response
            parsed_data = self._extract_json(response.text)

            # Validate and convert to ParsedReceipt
            receipt = self._validate_and_build_receipt(parsed_data)

            return receipt

        except Exception as e:
            print(f"❌ Gemini parsing error: {str(e)}")  # Better logging
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

    **THE "MATH VERIFICATION" RULE (CRITICAL):**
    To decide which number is the **UNIT PRICE**, you must perform a math check on every line:
    1. **Scenario A (3 Numbers):** You see `Qty`, `Num1`, and `Num2`.
       - Check: Does `Qty * Num1 ≈ Num2`?
       - If YES -> `Num1` is the Unit Price.
       - *Example:* `2 @ 90.25 180.50`. Since `2 * 90.25 = 180.50`, then **90.25** is the price. Do NOT divide 90.25 again.

    2. **Scenario B (2 Numbers):** You only see `Qty` and `Num1`.
       - Check: Is `Num1` surprisingly large compared to similar items?
       - Assume `Num1` is the **Line Total**.
       - Calculate: `Unit Price = Num1 / Qty`.
       - *Example:* `2 items ... 180.50`. Price is `90.25`.

    3. **Scenario C (Explicit Markers):** You see symbols like `@`, `P`, `ea`.
       - `@ 90.25` usually means 90.25 is the Unit Price.
       - `P15.00ea` means 15.00 is the Unit Price.

    **LAYOUT ADAPTATION:**
    - **Standard Columns:** `Qty | Name | Unit Price | Total`
    - **Split Line (Type 1):** Name on Line 1. `Qty @ Unit Price Total` on Line 2. (Common in Philippines).
    - **Split Line (Type 2):** `Qty Name Total` on Line 1. `Details @Unit` on Line 2.

    **Specific Examples to Guide You:**

    *Input (Willy Style):*
    "CREAM-O COOKIES
     2 @ PCK 90.25 180.50"
    *Analysis:* I see 2, 90.25, and 180.50. Math check: 2 * 90.25 = 180.50. Correct.
    *Output:* `{"name": "CREAM-O COOKIES", "qty": 2, "price": 90.25}`

    *Input (Ipil Style):*
    "2 PVC Adapter    20.00
      @P10.00ea"
    *Analysis:* I see Qty 2 and Total 20.00. I also see explicit "@P10.00ea".
    *Output:* `{"name": "PVC Adapter", "qty": 2, "price": 10.00}`

    **Parsing Rules:**
    1. **Store Name:** Extract from the top.
    2. **Date:** Find YYYY-MM-DD.
    3. **Items:** Remove `****` or codes like `885043` if they clutter the name.
    4. **Price:** Must ALWAYS be the price of ONE single item.
    """

            # Add OCR context if available
            if ocr_text:
                prompt += f"\n**OCR Extracted Text:**\n```\n{ocr_text[:2000]}\n```\n"

            if ocr_blocks:
                prompt += f"\n**Number of OCR blocks detected:** {len(ocr_blocks)}\n"

            prompt += "\n**Now output ONLY the JSON object, nothing else:**"

            return prompt

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
            if abs(receipt.total - items_sum) < 1.0:  # Within ₱1
                confidence_factors.append(0.95)
            else:
                confidence_factors.append(0.6)

        return sum(confidence_factors) / len(confidence_factors) if confidence_factors else 0.5