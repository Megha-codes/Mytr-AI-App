"""Tool definitions + dispatcher for the analytics chatbot (Groq
tool-calling). Every tool here is a thin pass-through to a real,
already-tested backend function — see each function's own module for the
actual logic. This file's only job is mapping a tool name + JSON
arguments to the right call, and shaping the result as plain
JSON-serializable data for the model to narrate. It never computes a
health number itself.

Deliberately absent: any tool that computes an insulin dose or any other
treatment/medication directive. There is no backend function to call for
that in the first place — this isn't just a system-prompt instruction
(services/chat/conversation.py's system prompt also says so explicitly),
it's a structural guarantee. The model cannot produce a real dose number
through tool-calling, because no tool exists that would return one.
"""

from __future__ import annotations

from datetime import date as date_type, datetime, timedelta, timezone
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from ...models.user import User
from ..analytics.weekly import build_weekly_analytics
from ..glucose.manual_log_service import log_manual_glucose_reading
from ..health.daily_rollup import local_date, local_date_bounds
from ..nutrition.log_meal_service import log_meal_for_user
from ..nutrition.meals_today import daily_nutrition_totals, list_meals_for_user, meal_label
from ..water.log_service import get_water_summary, log_water_entry

TOOL_SCHEMAS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "get_glucose_analytics",
            "description": (
                "Get the user's real glucose analytics: time-in-range breakdown, "
                "average glucose, GMI (an estimated A1c), the daily trend, and how "
                "recent meals affected glucose. Use this for any question about "
                "glucose levels, trends, control, or time-in-range."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "days": {"type": "integer", "description": "How many days back to analyze (default 7)."},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_meals",
            "description": "List the user's real logged meals over a recent period.",
            "parameters": {
                "type": "object",
                "properties": {
                    "days": {"type": "integer", "description": "How many days back (default 7)."},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_daily_nutrition",
            "description": (
                "Get the user's real total calories/carbs/protein/fat consumed on a "
                "given day (default today)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "date": {"type": "string", "description": "ISO date (YYYY-MM-DD). Defaults to today."},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_health_trends",
            "description": (
                "Get the user's real weekly trends for steps, sleep, HRV, resting "
                "heart rate, and water intake."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "days": {"type": "integer", "description": "How many days back (default 7)."},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_water_daily",
            "description": "Get the user's real water intake total for a given day (default today) against their daily goal.",
            "parameters": {
                "type": "object",
                "properties": {
                    "date": {"type": "string", "description": "ISO date (YYYY-MM-DD). Defaults to today."},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "log_meal",
            "description": (
                "Log a meal the user says they ate. Nutrition is resolved automatically "
                "by the backend (an Indian food database first, then a general food "
                "database, then a rough estimate as a last resort) — never state or "
                "estimate nutrition numbers yourself, always call this tool and report "
                "back exactly what it returns."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "food_name": {
                        "type": "string",
                        "description": "What the user ate, e.g. 'roti', 'chicken biryani'.",
                    },
                    "portion_grams": {
                        "type": "integer",
                        "description": (
                            "Estimated portion size in grams. Use a reasonable typical "
                            "serving if the user didn't say (e.g. one roti ≈ 40g, one "
                            "glass of milk ≈ 240g)."
                        ),
                    },
                },
                "required": ["food_name", "portion_grams"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "log_water",
            "description": "Log water the user says they drank.",
            "parameters": {
                "type": "object",
                "properties": {
                    "amount_ml": {
                        "type": "integer",
                        "description": "Amount in ml. A standard glass is 250ml if the user just says 'a glass'.",
                    },
                },
                "required": ["amount_ml"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "log_manual_glucose",
            "description": "Log a glucose reading the user reports, e.g. 'my glucose is 140 right now'.",
            "parameters": {
                "type": "object",
                "properties": {
                    "value_mgdl": {"type": "integer", "description": "Glucose value in mg/dL."},
                },
                "required": ["value_mgdl"],
            },
        },
    },
]


async def execute_tool(name: str, arguments: dict[str, Any], db: AsyncSession, user: User) -> dict[str, Any]:
    """Runs the real backend function for `name` and returns a plain,
    JSON-serializable dict — this is what gets fed back to the model as
    the tool result. Never raises past here: a request the tool can't
    satisfy (an out-of-range glucose value, a missing required argument)
    comes back as {"error": "..."} so the model narrates the failure
    instead of the whole turn blowing up with a 500.
    """
    try:
        handler = _HANDLERS.get(name)
        if handler is None:
            return {"error": f"Unknown tool: {name}"}
        return await handler(db, user, arguments)
    except Exception as exc:  # noqa: BLE001 - must always return a result, not raise
        return {"error": str(exc)}


def _parse_date(value: Any) -> date_type | None:
    if not value:
        return None
    return date_type.fromisoformat(value)


async def _get_glucose_analytics(db: AsyncSession, user: User, args: dict) -> dict:
    days = int(args.get("days") or 7)
    analytics = await build_weekly_analytics(db, user.id, user.timezone, window_days=days)
    g = analytics.glucose
    return {
        "has_data": g.has_data,
        "average_mgdl": g.average_mgdl,
        "gmi_percent": g.gmi_percent,
        "reading_count": g.reading_count,
        "time_in_range": None if not g.tir else {
            "below_target_pct": round(g.tir.below * 100, 1),
            "in_target_pct": round(g.tir.target * 100, 1),
            "above_target_pct": round(g.tir.above * 100, 1),
        },
        "daily": [
            {"date": d.date.isoformat(), "avg_mgdl": d.avg_mgdl, "min_mgdl": d.min_mgdl, "max_mgdl": d.max_mgdl}
            for d in g.daily
        ],
        "meals_affecting_glucose": [
            {
                "meal": c.label,
                "baseline_mgdl": c.baseline_mgdl,
                "post_meal_mgdl": c.post_meal_mgdl,
                "delta_mgdl": c.delta_mgdl,
                "window": c.window,
            }
            for c in analytics.food_glucose_correlations
        ],
    }


async def _get_meals(db: AsyncSession, user: User, args: dict) -> dict:
    days = int(args.get("days") or 7)
    since = datetime.now(timezone.utc) - timedelta(days=days)
    meals = await list_meals_for_user(db, user.id, from_=since)
    return {
        "count": len(meals),
        "meals": [
            {
                "name": meal_label(m.food_items or []),
                "meal_time": m.meal_time.isoformat(),
                "calories": m.total_calories,
                "carbs_g": float(m.total_carbs_g) if m.total_carbs_g is not None else None,
                "nutrition_source": m.nutrition_source,
            }
            for m in meals
        ],
    }


async def _get_daily_nutrition(db: AsyncSession, user: User, args: dict) -> dict:
    target_date = _parse_date(args.get("date")) or local_date(datetime.now(timezone.utc), user.timezone)
    range_start, range_end = local_date_bounds(target_date, user.timezone)
    totals = await daily_nutrition_totals(db, user.id, range_start, range_end, target_date)
    return {
        "date": totals.date.isoformat(),
        "consumed_kcal": totals.consumed_kcal,
        "carbs_g": totals.carbs_g,
        "protein_g": totals.protein_g,
        "fat_g": totals.fat_g,
        "fiber_g": totals.fiber_g,
        "meal_count": len(totals.meals),
    }


async def _get_health_trends(db: AsyncSession, user: User, args: dict) -> dict:
    days = int(args.get("days") or 7)
    analytics = await build_weekly_analytics(db, user.id, user.timezone, window_days=days)
    h = analytics.health_trends

    def _trend(t):
        return {
            "has_data": t.has_data,
            "unit": t.unit,
            "daily": [{"date": p.date.isoformat(), "value": p.value} for p in t.daily],
        }

    return {
        "steps": _trend(h.steps),
        "sleep_minutes": _trend(h.sleep_minutes),
        "hrv": _trend(h.hrv),
        "resting_heart_rate": _trend(h.resting_heart_rate),
        "water_ml": _trend(h.water_ml),
    }


async def _get_water_daily(db: AsyncSession, user: User, args: dict) -> dict:
    target_date = _parse_date(args.get("date"))
    summary = await get_water_summary(db, user, target_date)
    return {"date": summary.date.isoformat(), "total_ml": summary.total_ml, "goal_ml": summary.goal_ml}


async def _log_meal(db: AsyncSession, user: User, args: dict) -> dict:
    food_name = args.get("food_name")
    if not food_name:
        return {"error": "food_name is required"}
    portion_grams = int(args.get("portion_grams") or 100)

    result = await log_meal_for_user(db, user, food_name, portion_grams)
    return {
        "meal_id": str(result.meal_log.id),
        "food_name": food_name,
        "portion_grams": portion_grams,
        "calories": result.calories,
        "carbs_g": result.carbs_g,
        "protein_g": result.protein_g,
        "fat_g": result.fat_g,
        "fiber_g": result.fiber_g,
        "nutrition_source": result.source,
        "nutrition_verified": result.verified,
    }


async def _log_water(db: AsyncSession, user: User, args: dict) -> dict:
    amount_ml = args.get("amount_ml")
    if not amount_ml or amount_ml <= 0:
        return {"error": "amount_ml must be a positive number"}
    total = await log_water_entry(db, user, int(amount_ml))
    return {"logged_ml": int(amount_ml), "total_ml_today": total}


async def _log_manual_glucose(db: AsyncSession, user: User, args: dict) -> dict:
    value_mgdl = args.get("value_mgdl")
    if value_mgdl is None:
        return {"error": "value_mgdl is required"}
    try:
        reading_id = await log_manual_glucose_reading(user.id, int(value_mgdl), datetime.now(timezone.utc))
    except ValueError as exc:
        return {"error": str(exc)}
    return {"reading_id": reading_id, "value_mgdl": int(value_mgdl)}


_HANDLERS = {
    "get_glucose_analytics": _get_glucose_analytics,
    "get_meals": _get_meals,
    "get_daily_nutrition": _get_daily_nutrition,
    "get_health_trends": _get_health_trends,
    "get_water_daily": _get_water_daily,
    "log_meal": _log_meal,
    "log_water": _log_water,
    "log_manual_glucose": _log_manual_glucose,
}
