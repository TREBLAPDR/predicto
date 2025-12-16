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
    # 1. RECEIPT PARSING (With Math Verification)
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
        prompt = self._build_receipt_prompt(ocr_text, ocr_blocks)

        try:
            loop = asyncio.get_event_loop()

            if image_base64:
                image_bytes = base64.b64decode(image_base64)
                image = Image.open(BytesIO(image_bytes))

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

            parsed_data = self._extract_json(response.text)
            receipt = self._validate_and_build_receipt(parsed_data)
            return receipt

        except Exception as e:
            print(f"❌ Gemini parsing error: {str(e)}")
            return ParsedReceipt(parsingConfidence=0.0, items=[])

    # =========================================================
    # 2. AI SUGGESTIONS (FIXED VERSION)
    # =========================================================

    async def generate_suggestions(self, purchase_history: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Generate shopping suggestions based on purchase history
        FIXED: Better prompt, no strict JSON mode, better error handling
        """
        prompt = self._build_suggestion_prompt_v2(purchase_history)

        try:
            loop = asyncio.get_event_loop()

            print("🤖 [DEBUG] Sending request to Gemini...")
            print(f"📝 [DEBUG] History items: {len(purchase_history)}")

            response = await loop.run_in_executor(
                None,
                partial(
                    self.suggestion_model.generate_content,
                    prompt,
                    generation_config=genai.types.GenerationConfig(
                        temperature=0.7,
                        max_output_tokens=4000,
                    )
                )
            )

            print(f"📥 [DEBUG] Raw response length: {len(response.text)}")
            print(f"📥 [DEBUG] First 500 chars: {response.text[:500]}")

            if len(response.text) > 0 and not response.text.rstrip().endswith('}'):
                print("⚠️ [DEBUG] Response appears truncated, missing closing brace")

            print(f"📥 [DEBUG] FULL RESPONSE:\n{response.text}")

            result = self._extract_json(response.text)

            if not result:
                print("❌ [DEBUG] Failed to extract JSON from response")
                return []

            suggestions = result.get('suggestions', [])
            print(f"✅ [DEBUG] Extracted {len(suggestions)} suggestions")

            valid_suggestions = []
            for s in suggestions:
                if 'name' in s and 'category' in s:
                    valid_suggestions.append(s)
                else:
                    print(f"⚠️ [DEBUG] Skipping invalid suggestion: {s}")

            return valid_suggestions

        except Exception as e:
            print(f"❌ Gemini suggestion error: {str(e)}")
            import traceback
            print(f"📋 Stack trace: {traceback.format_exc()}")
            return []

    # =========================================================
    # 3. IMPROVED PROMPT BUILDER
    # =========================================================

    def _build_suggestion_prompt_v2(self, history: List[Dict[str, Any]]) -> str:
        """
        IMPROVED: More explicit examples and clearer instructions
        """
        history_text = "**Purchase History:**\n"
        for idx, item in enumerate(history[:20], 1):
            days = item.get('days_ago', 0)
            freq = item.get('frequency', 'unknown')
            history_text += f"{idx}. {item['name']} ({item['category']}) - Last bought {days} days ago"
            if freq and freq != 'unknown':
                history_text += f", usually every {freq:.1f} days"
            history_text += f"\n"

        return f"""You are an intelligent shopping assistant analyzing purchase patterns.

{history_text}

**YOUR TASK:**
Generate 5-10 smart shopping suggestions based on this purchase history.

**SUGGESTION LOGIC:**
1. **Replenishment Items**: Items that are due for repurchase based on frequency
   - Example: If milk is bought every 7 days and was last bought 10 days ago → SUGGEST IT

2. **Complementary Items**: Items commonly bought together
   - Example: If pasta was bought recently → suggest pasta sauce, cheese, or ground beef

3. **Seasonal/Pattern Items**: Items that fit user's shopping patterns
   - Example: If user buys personal care items regularly → suggest items in that category

4. **Smart Defaults**: If history is limited, suggest common household essentials
   - Examples: Rice, Eggs, Bread, Cooking Oil, Sugar, Salt

**CONFIDENCE SCORING:**
- 0.9-1.0: Definitely needed (overdue replenishment)
- 0.7-0.8: Highly likely (complementary or seasonal)
- 0.5-0.6: Good suggestion (pattern-based)

**OUTPUT FORMAT:**
Return ONLY a JSON object (no markdown, no explanation) with this structure:

{{
  "suggestions": [
    {{
      "name": "Bear Brand Powdered Milk 300g",
      "category": "Dairy",
      "confidence": 0.95,
      "reason": "Last purchased 10 days ago, usually bought every 7 days",
      "estimatedPrice": 110.0
    }},
    {{
      "name": "Pasta Sauce",
      "category": "Pantry",
      "confidence": 0.75,
      "reason": "You bought pasta 2 days ago, sauce is often needed",
      "estimatedPrice": 75.0
    }}
  ]
}}

**IMPORTANT RULES:**
- Generate AT LEAST 5 suggestions
- DO NOT return an empty suggestions array
- Use realistic Philippine product names and prices
- Each suggestion must have: name, category, confidence, reason, estimatedPrice
- Make the "reason" field personalized and specific

Now generate the suggestions based on the purchase history above."""

    # =========================================================
    # 4. ORIGINAL RECEIPT PROMPT (UNCHANGED)
    # =========================================================

    def _build_receipt_prompt(self, ocr_text: Optional[str], ocr_blocks: Optional[list]) -> str:
        """
        Restored prompt with the critical Math Verification Rules
        """
        prompt = """You are an expert receipt parser. Analyze this receipt image or OCR text and extract structured information.

**CRITICAL: You must respond with ONLY valid JSON. No markdown, no explanation.**

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

        return prompt

    # =========================================================
    # 5. IMPROVED JSON EXTRACTION
    # =========================================================

    def _extract_json(self, response_text: str) -> Dict[str, Any]:
        """
        IMPROVED: Better JSON extraction with multiple fallback strategies
        """
        text = response_text.strip()

        # Strategy 1: Remove markdown code fences first
        if text.startswith('```'):
            text = re.sub(r'^```(?:json)?\s*', '', text)
            text = re.sub(r'\s*```\s*$', '', text)
            text = text.strip()

        # Strategy 2: Direct JSON parse (after cleaning)
        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            print(f"⚠️ [DEBUG] JSON parse error: {str(e)}")

        # Strategy 3: Extract from markdown code blocks (if still present)
        json_pattern = r'```json\s*(\{.*?\})\s*```'
        generic_pattern = r'```\s*(\{.*?\})\s*```'

        for pattern in [json_pattern, generic_pattern]:
            match = re.search(pattern, response_text, re.DOTALL)
            if match:
                try:
                    return json.loads(match.group(1))
                except Exception as e:
                    print(f"⚠️ [DEBUG] Pattern extraction failed: {str(e)}")
                    continue

        # Strategy 4: Find first { to last } in original text
        start = response_text.find('{')
        end = response_text.rfind('}')
        if start != -1 and end != -1 and end > start:
            try:
                json_str = response_text[start:end+1]
                return json.loads(json_str)
            except Exception as e:
                print(f"⚠️ [DEBUG] Brace extraction failed: {str(e)}")

        print(f"⚠️ [DEBUG] All extraction strategies failed")
        print(f"⚠️ [DEBUG] Response preview: {response_text[:300]}")
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