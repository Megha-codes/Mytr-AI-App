from dataclasses import dataclass, field


@dataclass
class RawFoodItem:
    name: str
    portion_grams: float
    calories: float
    carbs_g: float
    protein_g: float
    fat_g: float
    fiber_g: float = 0.0
    confidence: float = 1.0


@dataclass
class EnrichedFoodItem:
    name: str
    portion_grams: float
    calories: float
    carbs_g: float
    protein_g: float
    fat_g: float
    fiber_g: float
    glycaemic_index: int
    glycaemic_load: float
    confidence: float


@dataclass
class EnrichedMeal:
    food_items: list[EnrichedFoodItem]
    total_calories: int
    total_carbs_g: float
    total_protein_g: float
    total_fat_g: float
    total_fiber_g: float
    glycaemic_load: float
    recognition_confidence: float


# Glycaemic Index reference table — Indian foods included
# Source: Harvard Medical School GL tables + Indian food GI research
GLYCAEMIC_INDEX_TABLE: dict[str, int] = {
    # Staples
    "white rice": 72,
    "brown rice": 50,
    "chapati": 52,
    "roti": 52,
    "paratha": 55,
    "idli": 35,
    "dosa": 40,
    "masala dosa": 40,
    "upma": 44,
    "poha": 55,
    "white bread": 75,
    "whole wheat bread": 69,
    # Pulses (low GI — important for Indian diet)
    "dal": 25,
    "rajma": 24,
    "chole": 28,
    "sambar": 30,
    # Vegetables
    "potato": 78,
    "sweet potato": 63,
    "peas": 48,
    # Snacks
    "vada": 58,
    "samosa": 55,
    "biscuit": 70,
    # Default for unrecognised items
    "default": 60,
}


class MealEnrichmentService:

    def enrich(
        self,
        food_items: list[RawFoodItem],
        confidence: float = 1.0,
    ) -> EnrichedMeal:
        enriched: list[EnrichedFoodItem] = []
        total_calories = 0.0
        total_carbs_g = 0.0
        total_protein_g = 0.0
        total_fat_g = 0.0
        total_fiber_g = 0.0
        total_gl = 0.0

        for item in food_items:
            gi = self._lookup_gi(item.name)
            gl = (gi * item.carbs_g) / 100.0

            enriched.append(
                EnrichedFoodItem(
                    name=item.name,
                    portion_grams=item.portion_grams,
                    calories=item.calories,
                    carbs_g=item.carbs_g,
                    protein_g=item.protein_g,
                    fat_g=item.fat_g,
                    fiber_g=item.fiber_g,
                    glycaemic_index=gi,
                    glycaemic_load=round(gl, 1),
                    confidence=item.confidence,
                )
            )

            total_calories += item.calories
            total_carbs_g += item.carbs_g
            total_protein_g += item.protein_g
            total_fat_g += item.fat_g
            total_fiber_g += item.fiber_g
            total_gl += gl

        return EnrichedMeal(
            food_items=enriched,
            total_calories=round(total_calories),
            total_carbs_g=round(total_carbs_g, 1),
            total_protein_g=round(total_protein_g, 1),
            total_fat_g=round(total_fat_g, 1),
            total_fiber_g=round(total_fiber_g, 1),
            glycaemic_load=round(total_gl, 1),
            recognition_confidence=confidence,
        )

    def _lookup_gi(self, food_name: str) -> int:
        normalised = food_name.lower().strip()

        if normalised in GLYCAEMIC_INDEX_TABLE:
            return GLYCAEMIC_INDEX_TABLE[normalised]

        for key in GLYCAEMIC_INDEX_TABLE:
            if key in normalised or normalised in key:
                return GLYCAEMIC_INDEX_TABLE[key]

        return GLYCAEMIC_INDEX_TABLE["default"]
