import logging
from dataclasses import dataclass

import httpx

logger = logging.getLogger(__name__)

USDA_SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"
USDA_FOOD_URL = "https://api.nal.usda.gov/fdc/v1/food/{fdc_id}"

# Nutrient name → field mapping (USDA uses verbose names)
_NUTRIENT_MAP = {
    "calories": {"Energy"},
    "protein_g": {"Protein"},
    "carbs_g": {"Carbohydrate, by difference"},
    "fat_g": {"Total lipid (fat)"},
    "fiber_g": {"Fiber, total dietary"},
}


@dataclass
class NutritionPer100g:
    name: str
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float
    fdc_id: str


class USDAService:
    def __init__(self, api_key: str = "DEMO_KEY") -> None:
        self.api_key = api_key

    async def search(self, query: str, page_size: int = 10) -> list[NutritionPer100g]:
        params = {
            "query": query,
            "pageSize": page_size,
            "api_key": self.api_key,
        }

        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(USDA_SEARCH_URL, params=params)
            response.raise_for_status()

        data = response.json()
        results: list[NutritionPer100g] = []

        for food in data.get("foods", []):
            nutrition = self._extract_nutrients(food.get("foodNutrients", []))
            results.append(
                NutritionPer100g(
                    name=food.get("description", query),
                    calories=nutrition["calories"],
                    protein_g=nutrition["protein_g"],
                    carbs_g=nutrition["carbs_g"],
                    fat_g=nutrition["fat_g"],
                    fiber_g=nutrition["fiber_g"],
                    fdc_id=str(food.get("fdcId", "")),
                )
            )

        return results

    async def get_by_id(self, fdc_id: str) -> NutritionPer100g | None:
        params = {"api_key": self.api_key}

        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                USDA_FOOD_URL.format(fdc_id=fdc_id), params=params
            )
            if response.status_code == 404:
                return None
            response.raise_for_status()

        food = response.json()
        nutrition = self._extract_nutrients(food.get("foodNutrients", []))

        return NutritionPer100g(
            name=food.get("description", ""),
            calories=nutrition["calories"],
            protein_g=nutrition["protein_g"],
            carbs_g=nutrition["carbs_g"],
            fat_g=nutrition["fat_g"],
            fiber_g=nutrition["fiber_g"],
            fdc_id=str(fdc_id),
        )

    @staticmethod
    def _extract_nutrients(food_nutrients: list[dict]) -> dict[str, float]:
        result = {k: 0.0 for k in _NUTRIENT_MAP}

        for entry in food_nutrients:
            name = entry.get("nutrientName", "")
            value = float(entry.get("value", 0) or 0)
            unit = entry.get("unitName", "").upper()

            for field, names in _NUTRIENT_MAP.items():
                if name in names:
                    # For calories, prefer kcal over kJ
                    if field == "calories" and unit not in ("KCAL", ""):
                        continue
                    result[field] = value
                    break

        return result
