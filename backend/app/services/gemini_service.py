import base64
import json
import logging
import os
from dataclasses import dataclass

import httpx

logger = logging.getLogger(__name__)

GEMINI_API_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models"
    "/gemini-2.0-flash:generateContent"
)

_PROMPT = (
    "Identify all food items visible in this image. "
    "For each item provide:\n"
    "- name: common food name (lowercase)\n"
    "- portion: human-readable portion (e.g. '1 cup', '2 pieces', '200g')\n"
    "- portion_grams: estimated weight in grams as an integer\n\n"
    "Respond ONLY with a valid JSON array — no markdown, no explanation.\n"
    'Example: [{"name": "dal", "portion": "1 cup", "portion_grams": 200}]'
)


@dataclass
class GeminiFoodItem:
    name: str
    portion: str
    portion_grams: int


class GeminiVisionService:
    def __init__(self, api_key: str) -> None:
        self.api_key = api_key

    async def analyze_image(self, image_bytes: bytes) -> list[GeminiFoodItem]:
        image_b64 = base64.b64encode(image_bytes).decode("utf-8")

        payload = {
            "contents": [
                {
                    "parts": [
                        {"text": _PROMPT},
                        {
                            "inline_data": {
                                "mime_type": "image/jpeg",
                                "data": image_b64,
                            }
                        },
                    ]
                }
            ],
            "generationConfig": {
                "temperature": 0.2,
                "topP": 0.8,
                "maxOutputTokens": 1024,
            },
        }

        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{GEMINI_API_URL}?key={self.api_key}",
                json=payload,
            )
            response.raise_for_status()

        data = response.json()

        try:
            raw_text = data["candidates"][0]["content"]["parts"][0]["text"]
        except (KeyError, IndexError) as exc:
            logger.error("Unexpected Gemini response structure: %s", data)
            raise ValueError("Gemini returned an unexpected response") from exc

        items = self._parse_json(raw_text)
        return [
            GeminiFoodItem(
                name=item.get("name", "unknown food"),
                portion=item.get("portion", ""),
                portion_grams=int(item.get("portion_grams", 100)),
            )
            for item in items
        ]

    @staticmethod
    def _parse_json(text: str) -> list[dict]:
        text = text.strip()
        # Strip markdown code fences if Gemini wraps output despite instructions
        if text.startswith("```"):
            parts = text.split("```")
            # parts[1] is the fenced block; strip optional language tag
            text = parts[1].lstrip("json").strip()
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            logger.error("Failed to parse Gemini JSON: %s", text)
            raise ValueError(f"Could not parse Gemini response as JSON: {exc}") from exc
