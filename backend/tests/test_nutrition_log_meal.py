"""Tests for POST /nutrition/log-meal and POST /nutrition/log — specifically
the nutrition-source resolution wired in on top of the pre-existing
calc-and-save logic: which of ifct/usda/gemini_estimate/manual a meal's
macros came from, and portion scaling.
"""

from __future__ import annotations

import uuid

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.api import nutrition
from app.core.security import create_access_token
from app.database import get_db
from app.models.ifct_food import IFCTFood
from app.models.meal_log import MealLog
from app.services.gemini_service import GeminiNutritionEstimate
from app.services.usda_service import NutritionPer100g

from .conftest import build_sqlite_db, make_user


@pytest.fixture
async def app_and_db():
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(nutrition.router, prefix="/nutrition")
    app.dependency_overrides[get_db] = _get_db

    async with session_factory() as session:
        session.add(IFCTFood(
            id=uuid.uuid4(), code="A015", name="Rice, raw, milled",
            energy_kcal=356.4, available_carb_g=78.24, protein_g=7.94,
            fat_g=0.52, fibre_g=2.81, sugars_g=0.69,
        ))
        await session.commit()

    with TestClient(app) as client:
        yield client, session_factory

    await engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _get_meal(session_factory, meal_id: str) -> MealLog:
    async with session_factory() as session:
        result = await session.execute(select(MealLog).where(MealLog.id == meal_id))
        return result.scalar_one()


# ── /log-meal: explicit client-supplied macros (backward-compat path) ──────

async def test_log_meal_with_explicit_macros_is_stamped_usda(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.post(
        "/nutrition/log-meal",
        json={
            "food_name": "Chicken breast", "portion_grams": 150, "fdc_id": "171077",
            "calories_per_100g": 165, "protein_per_100g": 31, "carbs_per_100g": 0,
            "fat_per_100g": 3.6, "fiber_per_100g": 0,
        },
        headers=_auth(token),
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["nutrition_source"] == "usda"
    assert body["nutrition_verified"] is True
    assert body["calories"] == pytest.approx(165 * 1.5, abs=1)

    meal = await _get_meal(session_factory, body["meal_id"])
    assert meal.nutrition_source == "usda"
    assert meal.nutrition_verified is True


# ── /log-meal: server-side resolution, IFCT hit ─────────────────────────────

async def test_log_meal_resolves_via_ifct_when_present(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.post(
        "/nutrition/log-meal",
        json={"food_name": "Rice, raw, milled", "portion_grams": 100},
        headers=_auth(token),
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["nutrition_source"] == "ifct"
    assert body["nutrition_verified"] is True
    # 100g portion == the per-100g IFCT value directly (rounded to 1dp by
    # meal_enrichment_service).
    assert body["carbs_g"] == pytest.approx(78.24, abs=0.1)
    assert body["calories"] == pytest.approx(356.4, abs=1)


async def test_log_meal_ifct_scales_by_portion(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.post(
        "/nutrition/log-meal",
        json={"food_name": "Rice, raw, milled", "portion_grams": 50},
        headers=_auth(token),
    )
    body = resp.json()
    # Half a 100g portion -> half the per-100g carbs.
    assert body["carbs_g"] == pytest.approx(78.24 / 2, abs=0.2)


# ── /log-meal: server-side resolution, dosa misses IFCT -> USDA fallback ───

async def test_log_meal_dosa_misses_ifct_and_falls_back_to_usda(app_and_db, monkeypatch):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    async def fake_search(query, page_size=1):
        assert query == "dosa"
        return [NutritionPer100g(
            name="Dosa, plain", calories=168, protein_g=3.9, carbs_g=28.5,
            fat_g=4.2, fiber_g=1.1, fdc_id="99999",
        )]
    monkeypatch.setattr(nutrition.usda_service, "search", fake_search)

    resp = client.post(
        "/nutrition/log-meal",
        json={"food_name": "dosa", "portion_grams": 100},
        headers=_auth(token),
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["nutrition_source"] == "usda"
    assert body["nutrition_verified"] is True
    assert body["carbs_g"] == pytest.approx(28.5, abs=0.1)


async def test_log_meal_falls_back_to_gemini_estimate_when_nothing_matches(app_and_db, monkeypatch):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    async def empty_search(query, page_size=1):
        return []
    monkeypatch.setattr(nutrition.usda_service, "search", empty_search)

    async def fake_estimate(food_name):
        return GeminiNutritionEstimate(
            calories_per_100g=210, protein_per_100g=5.0, carbs_per_100g=30.0,
            fat_per_100g=6.5, fiber_per_100g=2.0,
        )
    monkeypatch.setattr(nutrition.gemini_service, "estimate_nutrition", fake_estimate)

    resp = client.post(
        "/nutrition/log-meal",
        json={"food_name": "some obscure regional dish", "portion_grams": 100},
        headers=_auth(token),
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["nutrition_source"] == "gemini_estimate"
    assert body["nutrition_verified"] is False
    assert body["carbs_g"] == pytest.approx(30.0, abs=0.1)


# ── /log: manual entry ───────────────────────────────────────────────────

async def test_manual_log_is_stamped_manual_and_verified(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.post(
        "/nutrition/log",
        json={
            "name": "Home-cooked dal", "calories": 220, "carbs_g": 30,
            "protein_g": 12, "fat_g": 5, "meal_time": "2026-08-10T12:00:00Z",
        },
        headers=_auth(token),
    )
    assert resp.status_code == 200
    meal_id = resp.json()["meal_log_id"]

    meal = await _get_meal(session_factory, meal_id)
    assert meal.nutrition_source == "manual"
    assert meal.nutrition_verified is True


async def test_log_meal_requires_authentication(app_and_db):
    client, _ = app_and_db
    resp = client.post("/nutrition/log-meal", json={"food_name": "rice", "portion_grams": 100})
    assert resp.status_code == 401
