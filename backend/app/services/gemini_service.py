import base64
import json
import logging
import os
from dataclasses import dataclass

import httpx

logger = logging.getLogger(__name__)

# Google retired the generateContent REST API this model was originally
# written against (gemini-2.0-flash, then gemini-2.5-flash, both 404 as of
# 2026-08-11 — "no longer available to new users") in favor of the
# Interactions API. Different endpoint, different request/response shape
# entirely — this isn't just a model-name swap.
#
# Verified live against the production key before writing this (not from
# docs alone, which gave inconsistent v1beta vs v1beta2 paths):
#   curl -X POST ".../v1beta/interactions?key=..." -d '{"model":
#   "gemini-3.6-flash", "input": [{"type": "text", "text": "..."}]}'
# returned a real 200 with a completed interaction. v1beta (not v1beta2).
GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/interactions"
GEMINI_MODEL = "gemini-3.6-flash"

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
            "model": GEMINI_MODEL,
            "input": [
                {"type": "text", "text": _PROMPT},
                {"type": "image", "mime_type": "image/jpeg", "data": image_b64},
            ],
        }

        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{GEMINI_API_URL}?key={self.api_key}",
                json=payload,
            )
            response.raise_for_status()

        raw_text = self._extract_output_text(response.json())
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
            "model": GEMINI_MODEL,
            "input": [
                {"type": "text", "text": _NUTRITION_ESTIMATE_PROMPT.format(food_name=food_name)}
            ],
        }

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{GEMINI_API_URL}?key={self.api_key}",
                    json=payload,
                )
                response.raise_for_status()
            raw_text = self._extract_output_text(response.json())
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
    def _extract_output_text(data: dict) -> str:
        """Pulls the model's text out of an Interactions API response.

        There's no top-level `output_text` convenience field in the raw
        REST JSON (that only exists in Google's client SDKs) — the real
        text lives inside `steps`, on whichever step has `type ==
        "model_output"` (earlier steps can be `"thought"` entries, which
        this must skip). Joins multiple text content parts on that step,
        defensively, in case a response ever splits its output across more
        than one.
        """
        try:
            steps = data["steps"]
            model_output = next(s for s in steps if s.get("type") == "model_output")
            return "".join(
                part["text"] for part in model_output["content"] if part.get("type") == "text"
            )
        except (KeyError, StopIteration, TypeError) as exc:
            logger.error("Unexpected Gemini response structure: %s", data)
            raise ValueError("Gemini returned an unexpected response") from exc

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
