"""Tests for the previously-missing app-facing nutrition endpoints
(architecture-v3.md §2.5): GET /nutrition/meals, PATCH /nutrition/meals/{id},
DELETE /nutrition/meals/{id}, GET /nutrition/daily.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import select, text

from app.api import nutrition
from app.core.security import create_access_token
from app.database import get_db
from app.models.meal_log import MealLog

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

    with TestClient(app) as client:
        yield client, session_factory

    await engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _token_for(session_factory, email: str) -> tuple:
    user = await make_user(session_factory, email)
    return user, create_access_token(subject=str(user.id), token_version=user.token_version)


async def _insert_meal(
    session_factory, user_id, meal_time, name, calories=300, carbs_g=40.0,
    source="usda", verified=True,
) -> str:
    """Raw-SQL insert, matching test_device_health_calories_heartbeat.py's
    helper — for tests exercising GET /daily, which (like the device twin
    it mirrors) reads via meals_today.py's raw SQL, comparing user_id as a
    plain dashed string. Don't reuse this for list/patch/delete tests (see
    _insert_meal_orm) — those query through the typed ORM column instead,
    which on sqlite serializes UUIDs as undashed hex (tests/conftest.py's
    PG_UUID shim), not `str(uuid)`'s dashed form. Real Postgres has no such
    split (native UUID comparison is representation-independent); this
    divergence is a sqlite-test-harness-only concern, not anything the app
    itself needs to reconcile.
    """
    meal_id = str(uuid.uuid4())
    async with session_factory() as session:
        await session.execute(
            text("""
                INSERT INTO meal_logs
                    (id, user_id, meal_time, food_items, total_calories, total_carbs_g,
                     total_protein_g, total_fat_g, total_fiber_g, glycaemic_load,
                     nutrition_source, nutrition_verified)
                VALUES
                    (:id, :user_id, :meal_time, :food_items, :calories, :carbs_g,
                     :protein_g, :fat_g, :fiber_g, :gl, :source, :verified)
            """),
            {
                "id": meal_id, "user_id": str(user_id), "meal_time": meal_time,
                "food_items": json.dumps([{"name": name}]), "calories": calories,
                "carbs_g": carbs_g, "protein_g": 10.0, "fat_g": 8.0, "fiber_g": 3.0,
                "gl": 20.0, "source": source, "verified": verified,
            },
        )
        await session.commit()
    return meal_id


async def _insert_meal_orm(
    session_factory, user_id, meal_time, name, calories=300, carbs_g=40.0,
    source="usda", verified=True,
) -> str:
    """ORM insert — for list/patch/delete tests, which query through the
    typed MealLog.user_id/.id columns. Also more realistic: every meal
    those endpoints actually see in production was itself created via
    nutrition.py's own `db.add(MealLog(...))` (log-meal), not raw SQL.
    """
    async with session_factory() as session:
        meal = MealLog(
            user_id=user_id, meal_time=meal_time, food_items=[{"name": name}],
            total_calories=calories, total_carbs_g=carbs_g, total_protein_g=10.0,
            total_fat_g=8.0, total_fiber_g=3.0, glycaemic_load=20.0,
            nutrition_source=source, nutrition_verified=verified,
        )
        session.add(meal)
        await session.commit()
        await session.refresh(meal)
        return str(meal.id)


# ── GET /meals ───────────────────────────────────────────────────────────

async def test_list_meals_requires_authentication(app_and_db):
    client, _ = app_and_db
    resp = client.get("/nutrition/meals")
    assert resp.status_code == 401


async def test_list_meals_returns_only_the_caller_own_meals(app_and_db):
    client, session_factory = app_and_db
    user_a, token_a = await _token_for(session_factory, "a@example.com")
    user_b, _token_b = await _token_for(session_factory, "b@example.com")

    now = datetime.now(timezone.utc)
    await _insert_meal_orm(session_factory, user_a.id, now, "Poha")
    await _insert_meal_orm(session_factory, user_b.id, now, "Someone else's dosa")

    resp = client.get("/nutrition/meals", headers=_auth(token_a))
    assert resp.status_code == 200
    names = [m["food_name"] for m in resp.json()["meals"]]
    assert names == ["Poha"]


async def test_list_meals_honors_from_and_to(app_and_db):
    client, session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")

    now = datetime.now(timezone.utc)
    old = now - timedelta(days=10)
    await _insert_meal_orm(session_factory, user.id, now, "Recent meal")
    await _insert_meal_orm(session_factory, user.id, old, "Old meal")

    resp = client.get(
        "/nutrition/meals",
        params={"from": (now - timedelta(days=1)).isoformat()},
        headers=_auth(token),
    )
    names = [m["food_name"] for m in resp.json()["meals"]]
    assert names == ["Recent meal"]


async def test_list_meals_includes_nutrition_source(app_and_db):
    client, session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    now = datetime.now(timezone.utc)
    await _insert_meal_orm(session_factory, user.id, now, "Dal", source="ifct", verified=True)

    resp = client.get("/nutrition/meals", headers=_auth(token))
    meal = resp.json()["meals"][0]
    assert meal["nutrition_source"] == "ifct"
    assert meal["nutrition_verified"] is True


# ── PATCH /meals/{id} ────────────────────────────────────────────────────

async def test_patch_meal_requires_authentication(app_and_db):
    client, _ = app_and_db
    resp = client.patch(f"/nutrition/meals/{uuid.uuid4()}", json={"carbs_g": 10})
    assert resp.status_code == 401


async def test_patch_meal_updates_fields_and_marks_user_corrected(app_and_db):
    client, session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    now = datetime.now(timezone.utc)
    meal_id = await _insert_meal_orm(session_factory, user.id, now, "Poha", calories=300, carbs_g=40.0)

    resp = client.patch(
        f"/nutrition/meals/{meal_id}",
        json={"carbs_g": 55.0, "calories": 350},
        headers=_auth(token),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["carbs_g"] == 55.0
    assert body["calories"] == 350

    async with session_factory() as session:
        result = await session.execute(select(MealLog).where(MealLog.id == meal_id))
        meal = result.scalar_one()
    assert meal.user_corrected is True
    assert float(meal.total_carbs_g) == 55.0


async def test_patch_meal_recomputes_glycaemic_load_when_carbs_change(app_and_db):
    client, session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    now = datetime.now(timezone.utc)
    meal_id = await _insert_meal_orm(session_factory, user.id, now, "Rice", calories=300, carbs_g=40.0)

    original = client.get("/nutrition/meals", headers=_auth(token)).json()["meals"][0]["glycaemic_load"]

    resp = client.patch(f"/nutrition/meals/{meal_id}", json={"carbs_g": 80.0}, headers=_auth(token))
    updated = resp.json()["glycaemic_load"]

    assert updated != original


async def test_patch_meal_404s_for_another_users_meal(app_and_db):
    client, session_factory = app_and_db
    user_a, token_a = await _token_for(session_factory, "a@example.com")
    user_b, _token_b = await _token_for(session_factory, "b@example.com")
    meal_id = await _insert_meal_orm(session_factory, user_b.id, datetime.now(timezone.utc), "Not yours")

    resp = client.patch(f"/nutrition/meals/{meal_id}", json={"carbs_g": 1}, headers=_auth(token_a))
    assert resp.status_code == 404


async def test_patch_meal_404s_for_unknown_id(app_and_db):
    client, session_factory = app_and_db
    _user, token = await _token_for(session_factory, "a@example.com")
    resp = client.patch(f"/nutrition/meals/{uuid.uuid4()}", json={"carbs_g": 1}, headers=_auth(token))
    assert resp.status_code == 404


# ── DELETE /meals/{id} ───────────────────────────────────────────────────

async def test_delete_meal_removes_it(app_and_db):
    client, session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    meal_id = await _insert_meal_orm(session_factory, user.id, datetime.now(timezone.utc), "Poha")

    resp = client.delete(f"/nutrition/meals/{meal_id}", headers=_auth(token))
    assert resp.status_code == 204

    async with session_factory() as session:
        result = await session.execute(select(MealLog).where(MealLog.id == meal_id))
        assert result.scalar_one_or_none() is None


async def test_delete_meal_404s_for_another_users_meal(app_and_db):
    client, session_factory = app_and_db
    user_a, token_a = await _token_for(session_factory, "a@example.com")
    user_b, _token_b = await _token_for(session_factory, "b@example.com")
    meal_id = await _insert_meal_orm(session_factory, user_b.id, datetime.now(timezone.utc), "Not yours")

    resp = client.delete(f"/nutrition/meals/{meal_id}", headers=_auth(token_a))
    assert resp.status_code == 404

    async with session_factory() as session:
        result = await session.execute(select(MealLog).where(MealLog.id == meal_id))
        assert result.scalar_one_or_none() is not None  # untouched


# ── GET /daily ───────────────────────────────────────────────────────────

async def test_daily_requires_authentication(app_and_db):
    client, _ = app_and_db
    resp = client.get("/nutrition/daily")
    assert resp.status_code == 401


async def test_daily_with_no_meals_is_zeroed(app_and_db):
    client, session_factory = app_and_db
    _user, token = await _token_for(session_factory, "a@example.com")
    resp = client.get("/nutrition/daily", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["consumed_kcal"] == 0
    assert body["meals"] == []


async def test_daily_sums_todays_meals_correctly(app_and_db):
    client, session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    now = datetime.now(timezone.utc)
    await _insert_meal(session_factory, user.id, now, "Poha", calories=300, carbs_g=40.0)
    await _insert_meal(session_factory, user.id, now, "Dal", calories=220, carbs_g=30.0)
    yesterday = now - timedelta(days=1)
    await _insert_meal(session_factory, user.id, yesterday, "Old meal", calories=999, carbs_g=99.0)

    resp = client.get("/nutrition/daily", headers=_auth(token))
    body = resp.json()
    assert body["consumed_kcal"] == 520
    assert body["carbs_g"] == pytest.approx(70.0)
    assert len(body["meals"]) == 2


async def test_daily_matches_device_twin_shape_for_the_same_data(app_and_db):
    """GET /nutrition/daily is documented as the user-JWT twin of
    GET /device/calories/daily — same underlying aggregation
    (services/nutrition/meals_today.py), so the totals must agree."""
    from app.api import device_data
    from app.core.security import create_device_access_token
    from app.models.device import Device

    client, session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    now = datetime.now(timezone.utc)
    await _insert_meal(session_factory, user.id, now, "Poha", calories=300, carbs_g=40.0)

    user_daily = client.get("/nutrition/daily", headers=_auth(token)).json()

    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0))
        await session.commit()
    device_token = create_device_access_token(str(device_id), str(user.id), token_version=0)

    device_app = FastAPI()
    device_app.include_router(device_data.router)

    async def _get_db():
        async with session_factory() as session:
            yield session
    device_app.dependency_overrides[get_db] = _get_db

    with TestClient(device_app) as device_client:
        device_daily = device_client.get(
            "/device/calories/daily", headers={"Authorization": f"Bearer {device_token}"}
        ).json()

    assert user_daily["consumed_kcal"] == device_daily["consumed_kcal"]
    assert user_daily["carbs_g"] == device_daily["carbs_g"]
