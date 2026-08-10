"""Tests for services/nutrition/source_router.py — the IFCT -> USDA ->
Gemini-estimate priority chain used when a meal is logged from Gemini's
dish recognition.

USDA/Gemini are faked at the interface level (duck-typed stand-ins with an
async `search`/`estimate_nutrition` method matching the real services)
rather than mocked at the HTTP layer — this file is about proving the
router's *ordering and fallback* logic, not re-testing USDA/Gemini's own
HTTP handling (covered separately: test_gemini_nutrition_estimate.py).
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select

from app.models.ifct_food import IFCTFood
from app.services.gemini_service import GeminiNutritionEstimate
from app.services.nutrition.source_router import resolve_nutrition, search_ifct_foods
from app.services.usda_service import NutritionPer100g

from .conftest import build_sqlite_db


class FakeUSDAService:
    def __init__(self, results: list[NutritionPer100g] | None = None):
        self._results = results or []
        self.calls: list[str] = []

    async def search(self, query: str, page_size: int = 1) -> list[NutritionPer100g]:
        self.calls.append(query)
        return self._results


class FailingUSDAService:
    async def search(self, query: str, page_size: int = 1):
        raise RuntimeError("USDA is down")


class FakeGeminiService:
    def __init__(self, estimate: GeminiNutritionEstimate | None):
        self._estimate = estimate
        self.calls: list[str] = []

    async def estimate_nutrition(self, food_name: str):
        self.calls.append(food_name)
        return self._estimate


@pytest.fixture
async def ifct_db():
    engine, session_factory = await build_sqlite_db()
    async with session_factory() as session:
        # Real uuid4() values, not hand-picked ones ("1111...1111" etc.):
        # SQLite gives an untyped/unknown column NUMERIC storage affinity,
        # and an all-digit hex UUID string is exactly the kind of value
        # SQLite's affinity rules silently coerce to a float on write —
        # which then blows up the UUID result processor on read. Real
        # uuid4() output almost always contains a-f letters and never hits
        # this; it's a sqlite-test-harness quirk, not anything the app or
        # production Postgres would ever see.
        session.add(IFCTFood(
            id=uuid.uuid4(),
            code="A015", name="Rice, raw, milled",
            energy_kcal=356.4, available_carb_g=78.24, protein_g=7.94,
            fat_g=0.52, fibre_g=2.81, sugars_g=0.69,
        ))
        session.add(IFCTFood(
            id=uuid.uuid4(),
            code="J002", name="Banana, ripe, robusta",
            energy_kcal=90.0, available_carb_g=22.0, protein_g=1.2,
            fat_g=0.2, fibre_g=1.1, sugars_g=15.0,
        ))
        await session.commit()

    async with session_factory() as session:
        yield session

    await engine.dispose()


# ── search_ifct_foods ────────────────────────────────────────────────────

async def test_exact_case_insensitive_match_wins(ifct_db):
    hits = await search_ifct_foods(ifct_db, "rice, raw, milled")
    assert [h.code for h in hits] == ["A015"]


async def test_substring_match_on_sqlite_fallback(ifct_db):
    hits = await search_ifct_foods(ifct_db, "banana")
    assert any(h.code == "J002" for h in hits)


async def test_no_match_returns_empty_not_an_error(ifct_db):
    # "dosa" is the flagship example of a food IFCT2017's raw-ingredient
    # table doesn't have (see test_ifct_import.py) — asserting the empty
    # result here is what makes the USDA-fallback test below meaningful.
    hits = await search_ifct_foods(ifct_db, "dosa")
    assert hits == []


async def test_blank_query_returns_empty(ifct_db):
    assert await search_ifct_foods(ifct_db, "   ") == []


# ── resolve_nutrition: tier 1, IFCT hit ─────────────────────────────────────

async def test_resolves_via_ifct_when_present(ifct_db):
    usda = FakeUSDAService()
    resolved = await resolve_nutrition(ifct_db, "rice, raw, milled", usda)

    assert resolved.source == "ifct"
    assert resolved.verified is True
    assert resolved.ifct_code == "A015"
    assert resolved.carbs_per_100g == 78.24
    assert resolved.calories_per_100g == 356.4
    # IFCT hit -> USDA must never even be called.
    assert usda.calls == []


# ── resolve_nutrition: tier 2, USDA fallback ────────────────────────────────

async def test_falls_back_to_usda_when_ifct_has_no_match(ifct_db):
    usda = FakeUSDAService(results=[
        NutritionPer100g(
            name="Dosa, plain", calories=168, protein_g=3.9, carbs_g=28.5,
            fat_g=4.2, fiber_g=1.1, fdc_id="12345",
        )
    ])
    resolved = await resolve_nutrition(ifct_db, "dosa", usda)

    assert resolved.source == "usda"
    assert resolved.verified is True
    assert resolved.fdc_id == "12345"
    assert resolved.carbs_per_100g == 28.5
    assert usda.calls == ["dosa"]


async def test_usda_failure_falls_through_instead_of_raising(ifct_db):
    gemini = FakeGeminiService(GeminiNutritionEstimate(
        calories_per_100g=150, protein_per_100g=3, carbs_per_100g=25,
        fat_per_100g=3, fiber_per_100g=1,
    ))
    resolved = await resolve_nutrition(ifct_db, "dosa", FailingUSDAService(), gemini)

    assert resolved.source == "gemini_estimate"
    assert resolved.verified is False


# ── resolve_nutrition: tier 3, Gemini estimate ──────────────────────────────

async def test_falls_back_to_gemini_estimate_when_nothing_else_matches(ifct_db):
    usda = FakeUSDAService(results=[])
    gemini = FakeGeminiService(GeminiNutritionEstimate(
        calories_per_100g=210, protein_per_100g=5.0, carbs_per_100g=30.0,
        fat_per_100g=6.5, fiber_per_100g=2.0,
    ))
    resolved = await resolve_nutrition(ifct_db, "some obscure regional dish", usda, gemini)

    assert resolved.source == "gemini_estimate"
    assert resolved.verified is False
    assert resolved.calories_per_100g == 210
    assert gemini.calls == ["some obscure regional dish"]


async def test_all_three_sources_missing_returns_zeroed_unverified(ifct_db):
    usda = FakeUSDAService(results=[])
    gemini = FakeGeminiService(estimate=None)  # Gemini itself couldn't produce one either

    resolved = await resolve_nutrition(ifct_db, "totally unknown food", usda, gemini)

    assert resolved.source == "gemini_estimate"
    assert resolved.verified is False
    assert resolved.calories_per_100g == 0.0


async def test_no_gemini_service_configured_still_returns_a_result(ifct_db):
    usda = FakeUSDAService(results=[])
    resolved = await resolve_nutrition(ifct_db, "totally unknown food", usda, gemini_service=None)

    assert resolved.source == "gemini_estimate"
    assert resolved.verified is False
