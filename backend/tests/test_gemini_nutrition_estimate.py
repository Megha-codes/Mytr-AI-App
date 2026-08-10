"""Tests for GeminiVisionService.estimate_nutrition — the last-resort
nutrition source (services/nutrition/source_router.py) used when a food
matches neither IFCT nor USDA.
"""

from __future__ import annotations

import httpx
import pytest

from app.services.gemini_service import GeminiVisionService


def _patch_client(monkeypatch, handler):
    import app.services.gemini_service as mod

    # `mod.httpx` is the same module object `httpx` above refers to (module
    # imports are singletons) — capture the *real* AsyncClient before
    # patching, or the factory below would end up calling itself.
    real_async_client = httpx.AsyncClient

    def _factory(*, timeout):
        return real_async_client(transport=httpx.MockTransport(handler), timeout=timeout)

    monkeypatch.setattr(mod.httpx, "AsyncClient", _factory)


def _gemini_response(text: str) -> dict:
    return {"candidates": [{"content": {"parts": [{"text": text}]}}]}


async def test_returns_none_without_an_api_key():
    service = GeminiVisionService(api_key="")
    assert await service.estimate_nutrition("dosa") is None


async def test_parses_a_clean_json_estimate(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        body = _gemini_response(
            '{"calories": 168, "protein_g": 3.9, "carbs_g": 28.5, "fat_g": 4.2, "fiber_g": 1.1}'
        )
        return httpx.Response(200, json=body)

    _patch_client(monkeypatch, handler)
    service = GeminiVisionService(api_key="test-key")

    estimate = await service.estimate_nutrition("plain dosa")
    assert estimate is not None
    assert estimate.calories_per_100g == 168
    assert estimate.carbs_per_100g == 28.5
    assert estimate.protein_per_100g == 3.9
    assert estimate.fat_per_100g == 4.2
    assert estimate.fiber_per_100g == 1.1


async def test_strips_markdown_fences_before_parsing(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        body = _gemini_response('```json\n{"calories": 90, "protein_g": 1}\n```')
        return httpx.Response(200, json=body)

    _patch_client(monkeypatch, handler)
    service = GeminiVisionService(api_key="test-key")

    estimate = await service.estimate_nutrition("some fruit")
    assert estimate is not None
    assert estimate.calories_per_100g == 90
    # Fields the model omitted default to 0, not a crash.
    assert estimate.carbs_per_100g == 0.0


async def test_returns_none_on_unparseable_response(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_gemini_response("not json at all"))

    _patch_client(monkeypatch, handler)
    service = GeminiVisionService(api_key="test-key")

    assert await service.estimate_nutrition("mystery food") is None


async def test_returns_none_on_http_error(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"error": "down"})

    _patch_client(monkeypatch, handler)
    service = GeminiVisionService(api_key="test-key")

    assert await service.estimate_nutrition("dosa") is None


async def test_returns_none_on_unexpected_response_shape(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"candidates": []})

    _patch_client(monkeypatch, handler)
    service = GeminiVisionService(api_key="test-key")

    assert await service.estimate_nutrition("dosa") is None
