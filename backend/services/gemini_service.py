import google.generativeai as genai
from typing import Optional, Dict, Any, List
import json
import re
from PIL import Image
from io import BytesIO
import base64
import asyncio
from functools import partial
from datetime import datetime

from models.schemas import ParsedReceipt, ReceiptItem
from config import settings

class GeminiService:
    def __init__(self):
        if not settings.is_gemini_configured:
            raise ValueError("Gemini API key not configured. Please set GEMINI_API_KEY in .env")

        genai.configure(api_key=settings.GEMINI_API_KEY)

        # Model 1: Receipt Parser
        self.model = genai.GenerativeModel(settings.GEMINI_MODEL)

        # Model 2: AI Suggestion Engine (NEW)
        self.suggestion_model = genai.GenerativeModel(settings.GEMINI_MODEL_2)

    async def parse_receipt(
        self,
        image_base64: Optional[str] = None,
        ocr_text: Optional[str] = None,
        ocr_blocks: Optional[list] = None
    ) -> ParsedReceipt:
        """
        Parse receipt using Gemini Pro Vision API
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

    async def generate_suggestions(self, purchase_history: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Generate shopping suggestions based on purchase history using GEMINI_MODEL_2
        """
        prompt = self._build_suggestion_prompt(purchase_history)

        try:
            loop = asyncio.get_event_loop()

            # Use the SECOND model for reasoning
            response = await loop.run_in_executor(
                None,
                partial(
                    self.suggestion_model.generate_content,
                    prompt,
                    generation_config=genai.types.GenerationConfig(
                        temperature=0.7, # Slightly higher for creativity
                        max_output_tokens=1000,
                    )
                )
            )

            result = self._extract_json(response.text)
            return result.get('suggestions', [])

        except Exception as e:
            print(f"❌ Gemini suggestion error: {str(e)}")
            return []

    def _build_suggestion_prompt(self, history: List[Dict[str, Any]]) -> str:
        """
        Construct a context-aware prompt for the AI
        """
        current_date = datetime.now().strftime("%Y-%m-%d")

        # Convert history to a lightweight string format to save tokens
        history_str = json.dumps(history[:50], indent=2) # Limit to top 50 relevant items

        return f"""
        You are a smart shopping assistant. Today is {current_date}.

        Here is the user's recent product history with purchase stats:
        {history_str}

        **Your Task:**
        Suggest 5-10 items the user likely needs to buy NEXT.

        **Reasoning Logic:**
        1. **Depletion:** If they buy Milk every 7 days and last bought it 8 days ago, suggest it.
        2. **Complementary:** If they recently bought 'Burger Patties', suggest 'Buns' even if not in history.
        3. **Habit:** Identify weekly/monthly patterns.
        4. **Seasonality:** Suggest items relevant to the current month if applicable.

        **Output Format:**
        Return ONLY valid JSON containing a list of suggestions.
        {{
            "suggestions": [
                {{
                    "name": "Item Name",
                    "category": "Category Name",
                    "confidence": 0.95,
                    "reason": "You usually buy this every 7 days",
                    "estimatedPrice": 120.00
                }}
            ]
        }}
        """

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

**Parsing Rules:**
1. **Store Name:** Extract from the top.
2. **Date:** Find YYYY-MM-DD.
3. **Items:** Remove `****` or codes like `885043` if they clutter the name.
4. **Price:** Must ALWAYS be the price of ONE single item.
"""

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
        text = response_text.strip()
        json_match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, re.DOTALL)
        if json_match:
            text = json_match.group(1)

        start = text.find('{')
        end = text.rfind('}')

        if start == -1 or end == -1:
            return {}

        try:
            return json.loads(text[start:end+1])
        except json.JSONDecodeError as e:
            # Return empty dict on error instead of crashing
            return {}

    def _validate_and_build_receipt(self, data: Dict[str, Any]) -> ParsedReceipt:
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
                continue

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
        confidence_factors = []
        if receipt.storeName: confidence_factors.append(0.9)
        if receipt.date: confidence_factors.append(0.9)
        if receipt.items:
            avg_item_confidence = sum(item.confidence for item in receipt.items) / len(receipt.items)
            confidence_factors.append(avg_item_confidence)
        if receipt.total and receipt.items:
            items_sum = sum(item.price or 0 for item in receipt.items)
            if abs(receipt.total - items_sum) < 1.0:
                confidence_factors.append(0.95)
            else:
                confidence_factors.append(0.6)

        return sum(confidence_factors) / len(confidence_factors) if confidence_factors else 0.5