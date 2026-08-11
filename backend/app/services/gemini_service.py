import base64
import json
import logging
import os
from dataclasses import dataclass

import httpx

logger = logging.getLogger(__name__)

GEMINI_API_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models"
    "/gemini-2.5-flash:generateContent"
)
# gemini-2.0-flash was retired sometime after this was first written — a
# live `GET /v1beta/models` call against the production API key (2026-08-11)
# no longer lists it at all, which is what the "404 Not Found" on every
# analyze-image/estimate_nutrition call turned out to be. gemini-2.5-flash is
# the closest still-GA (non "-preview") equivalent: same fast/cheap tier this
# was chosen for originally, still multimodal (image input + JSON text out).

_PROMPT = (
    "Identify all food items visible in this image. "
    "For each item provide:\n"
    "- name: common food name (lowercase)\n"
    "- portion: human-readable portion (e.g. '1 cup', '2 pieces', '200g')\n"
    "- portion_grams: estimated weight in grams as an integer\n\n"
    "Respond ONLY with a valid JSON array — no markdown, no explanation.\n"
    'Example: [{"name": "dal", "portion": "1 cup", "portion_grams": 200}]'
)

# Last-resort nutrition source (services/nutrition/source_router.py), used
# only when a food matches neither IFCT nor USDA — e.g. a dish specific
# enough that neither database has it. Text-only prompt, no image.
_NUTRITION_ESTIMATE_PROMPT = (
    'Estimate typical nutrition per 100g of this food: "{food_name}".\n'
    "Respond ONLY with a valid JSON object — no markdown, no explanation.\n"
    'Example: {{"calories": 130, "protein_g": 2.7, "carbs_g": 28.2, '
    '"fat_g": 0.3, "fiber_g": 0.4}}'
)


@dataclass
class GeminiFoodItem:
    name: str
    portion: str
    portion_grams: int


@dataclass
class GeminiNutritionEstimate:
    """A rough, model-guessed per-100g estimate — never a database lookup.
    Callers (services/nutrition/source_router.py) must treat this as
    unverified data, distinct from a real IFCT/USDA hit."""

    calories_per_100g: float
    protein_per_100g: float
    carbs_per_100g: float
    fat_per_100g: float
    fiber_per_100g: float


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

    async def estimate_nutrition(self, food_name: str) -> GeminiNutritionEstimate | None:
        """Last-resort nutrition source: no IFCT/USDA match, so ask Gemini
        for a rough per-100g guess instead of leaving the meal at all-zero
        macros. Returns None (never raises) on any failure — missing API
        key, network error, or an unparseable response — since by the time
        this runs, two real lookups have already failed and the caller
        needs to decide what "nothing worked at all" means, not catch an
        exception from this specific tier.
        """
        if not self.api_key:
            return None

        payload = {
            "contents": [
                {"parts": [{"text": _NUTRITION_ESTIMATE_PROMPT.format(food_name=food_name)}]}
            ],
            "generationConfig": {
                "temperature": 0.2,
                "topP": 0.8,
                "maxOutputTokens": 256,
            },
        }

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{GEMINI_API_URL}?key={self.api_key}",
                    json=payload,
                )
                response.raise_for_status()
            data = response.json()
            raw_text = data["candidates"][0]["content"]["parts"][0]["text"]
            parsed = self._parse_json_object(raw_text)
            return GeminiNutritionEstimate(
                calories_per_100g=float(parsed.get("calories", 0) or 0),
                protein_per_100g=float(parsed.get("protein_g", 0) or 0),
                carbs_per_100g=float(parsed.get("carbs_g", 0) or 0),
                fat_per_100g=float(parsed.get("fat_g", 0) or 0),
                fiber_per_100g=float(parsed.get("fiber_g", 0) or 0),
            )
        except Exception:
            logger.warning("Gemini nutrition estimate failed for %r", food_name, exc_info=True)
            return None

    @staticmethod
    def _strip_markdown_fences(text: str) -> str:
        text = text.strip()
        if text.startswith("```"):
            parts = text.split("```")
            # parts[1] is the fenced block; strip optional language tag
            text = parts[1].lstrip("json").strip()
        return text

    @classmethod
    def _parse_json(cls, text: str) -> list[dict]:
        text = cls._strip_markdown_fences(text)
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            logger.error("Failed to parse Gemini JSON: %s", text)
            raise ValueError(f"Could not parse Gemini response as JSON: {exc}") from exc

    @classmethod
    def _parse_json_object(cls, text: str) -> dict:
        text = cls._strip_markdown_fences(text)
        return json.loads(text)
