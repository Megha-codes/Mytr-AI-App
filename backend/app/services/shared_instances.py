"""Singleton service instances shared across API routers and the
analytics chatbot's tool executor (services/chat/tools.py). Constructed
once here, not per-module, so app/api/nutrition.py and the chat tools
never end up with two different USDAService/GeminiVisionService clients
(different timeouts, different api_key resolution, etc.) for what must
behave identically either way.
"""

import os

from .gemini_service import GeminiVisionService
from .meal_enrichment_service import MealEnrichmentService
from .usda_service import USDAService

gemini_service = GeminiVisionService(api_key=os.getenv("GOOGLE_API_KEY", ""))
usda_service = USDAService(api_key=os.getenv("USDA_API_KEY", "DEMO_KEY"))
meal_enrichment_service = MealEnrichmentService()
