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

        # Model 1: Receipt Parser (Vision capabilities)
        self.model = genai.GenerativeModel(settings.GEMINI_MODEL)

        # Model 2: AI Suggestion Engine (Reasoning capabilities)
        self.suggestion_model = genai.GenerativeModel(settings.GEMINI_MODEL_2)

    # =========================================================
    # 1. RECEIPT PARSING
    # =========================================================

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
            print(f"❌ Gemini parsing error: {str(e)}")
            # Return empty/failed receipt rather than crashing
            return ParsedReceipt(parsingConfidence=0.0, items=[])

    # =========================================================
    # 2. AI SUGGESTIONS (AGGRESSIVE MODE)
    # =========================================================

    async def generate_suggestions(self, purchase_history: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Generate shopping suggestions based on purchase history using GEMINI_MODEL_2
        """
        prompt = self._build_suggestion_prompt(purchase_history)

        try:
            loop = asyncio.get_event_loop()

            # Use higher temperature for creativity and force JSON response
            response = await loop.run_in_executor(
                None,
                partial(
                    self.suggestion_model.generate_content,
                    prompt,
                    generation_config=genai.types.GenerationConfig(
                        temperature=0.6,
                        max_output_tokens=1000,
                        response_mime_type="application/json"
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
        history_str = json.dumps(history[:50], indent=2)

        return f"""
        You are a smart shopping assistant. Today is {current_date}.

        **User's Recent Purchase History:**
        {history_str}

        **Your Task:**
        Suggest 5 to 10 items the user likely needs to buy NEXT.

        **CRITICAL REASONING RULES (Follow Strictly):**
        1. **Complementary Items (Most Important):** If the user bought 'Toothpaste', suggest 'Mouthwash' or 'Floss'. If they bought 'Laundry Powder', suggest 'Fabric Softener' or 'Bleach'. Look for these logical pairs in the history.
        2. **Replenishment:** If an item was bought >7 days ago and is consumable (like Milk, Bread, Rice, Eggs), suggest it again.
        3. **Force Suggestions:** Even if the history is short or sparse, use the 'category' or 'name' to guess what else they might need. DO NOT return an empty list.
        4. **Variety:** Do not just suggest the exact same items unless they are overdue staples. Suggest related items from the same aisle.
        5. **Context:** 'days_ago: 0' means bought today. 'days_ago: 30' means bought a month ago.

        **Output Format:**
        Return ONLY valid JSON containing a list of suggestions.
        {{
            "suggestions": [
                {{
                    "name": "Fabric Softener",
                    "category": "Household",
                    "confidence": 0.85,
                    "reason": "Goes well with your recent detergent purchase",
                    "estimatedPrice": 85.00
                }}
            ]
        }}
        """

    # =========================================================
    # 3. HELPER METHODS
    # =========================================================

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
   - *Example:* `2 @ 90.25 180.50`. Since `2 * 90.25 = 180.50`, then **90.25** is the price.

2. **Scenario B (2 Numbers):** You only see `Qty` and `Num1`.
   - Check: Is `Num1` surprisingly large compared to similar items?
   - Assume `Num1` is the **Line Total**.
   - Calculate: `Unit Price = Num1 / Qty`.

3. **Scenario C (Explicit Markers):** You see symbols like `@`, `P`, `ea`.
   - `@ 90.25` usually means 90.25 is the Unit Price.

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
        Extract JSON from Gemini response, robustly handling markdown code blocks
        """
        text = response_text.strip()

        # Method 1: Try direct parse
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        # Method 2: Extract from ```json ... ``` markdown
        json_match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, re.DOTALL)
        if json_match:
            try:
                return json.loads(json_match.group(1))
            except:
                pass

        # Method 3: Fallback - look for the first { and last }
        start = text.find('{')
        end = text.rfind('}')
        if start != -1 and end != -1:
            try:
                return json.loads(text[start:end+1])
            except:
                pass

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