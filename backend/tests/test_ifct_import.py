"""Tests for scripts/import_ifct.py — the IFCT2017 -> `ifct_foods` loader.

Covers: per-row parsing (pure function, no DB), the kJ->kcal energy
conversion this whole import hinges on, and an end-to-end import of the
real CSV shipped in the repo (backend/ifct2017_compositions.csv) landing
sane per-100g values.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from sqlalchemy import select

from app.models.ifct_food import IFCTFood
from scripts.import_ifct import DEFAULT_CSV_PATH, KJ_PER_KCAL, import_csv, parse_csv, parse_row

from .conftest import build_sqlite_db

REAL_CSV = DEFAULT_CSV_PATH


# ── parse_row: pure function, no DB or file needed ─────────────────────────

def test_parse_row_maps_and_rounds_the_columns_we_keep():
    row = {
        "code": "A015", "name": "Rice, raw, milled",
        "choavldf": "78.24", "protcnt": "7.94", "fatce": "0.52",
        "fibtg": "2.81", "enerc": "1491", "fsugar": "0.69",
        # A handful of the ~240 columns we deliberately ignore.
        "water": "9.93", "ash": "0.56", "vitc": "0",
    }
    parsed = parse_row(row)
    assert parsed["code"] == "A015"
    assert parsed["name"] == "Rice, raw, milled"
    assert parsed["available_carb_g"] == 78.24
    assert parsed["protein_g"] == 7.94
    assert parsed["fat_g"] == 0.52
    assert parsed["fibre_g"] == 2.81
    assert parsed["sugars_g"] == 0.69
    # 1491 kJ / 4.184 = 356.4 kcal
    assert parsed["energy_kcal"] == pytest.approx(356.4, abs=0.1)


def test_parse_row_defaults_blank_numeric_cells_to_zero():
    row = {"code": "X1", "name": "Test food", "choavldf": "", "protcnt": None,
           "fatce": "1.0", "fibtg": "0", "enerc": "100", "fsugar": "0"}
    parsed = parse_row(row)
    assert parsed["available_carb_g"] == 0.0
    assert parsed["protein_g"] == 0.0
    assert parsed["fat_g"] == 1.0


def test_parse_row_skips_rows_missing_code_or_name():
    assert parse_row({"code": "", "name": "Something"}) is None
    assert parse_row({"code": "A1", "name": ""}) is None
    assert parse_row({"code": "A1", "name": "  "}) is None


def test_kj_per_kcal_is_the_standard_conversion_factor():
    # Sanity-pin the constant itself so a typo here can't silently corrupt
    # every imported food's energy value.
    assert KJ_PER_KCAL == pytest.approx(4.184)


# ── parse_csv against the real, repo-shipped CSV ────────────────────────────

@pytest.mark.skipif(not REAL_CSV.exists(), reason="ifct2017_compositions.csv not present")
def test_real_csv_has_no_prepared_dishes_only_raw_ingredients():
    """Documents a real gap in this dataset: IFCT2017's raw/single-ingredient
    composition table (what this CSV is) has no "Dosa", "Idli", "Chapati",
    etc. — those live in IFCT's separate recipe table, not exported here.
    A meal named "dosa" is expected to miss IFCT and fall through to
    USDA/Gemini (see test_nutrition_source_router.py) — this test exists so
    that if a future CSV *does* add prepared dishes, someone notices and can
    update the source-router fallback test's assumptions instead of it
    quietly going stale.
    """
    rows, _skipped = parse_csv(REAL_CSV)
    names_lower = {r["name"].lower() for r in rows}
    for dish in ("dosa", "idli", "chapati", "poori", "biryani"):
        assert not any(dish in n for n in names_lower), (
            f"{dish!r} now exists in the CSV — IFCT-hit assumptions in "
            "test_nutrition_source_router.py may need updating"
        )


@pytest.mark.skipif(not REAL_CSV.exists(), reason="ifct2017_compositions.csv not present")
async def test_import_real_csv_yields_sane_per_100g_values():
    engine, session_factory = await build_sqlite_db()
    async with session_factory() as session:
        stats = await import_csv(session, REAL_CSV)

    assert stats.imported > 500  # 542 rows in the shipped CSV as of writing
    assert stats.skipped == 0

    async with session_factory() as session:
        result = await session.execute(select(IFCTFood).where(IFCTFood.code == "A015"))
        rice = result.scalar_one()

    assert rice.name == "Rice, raw, milled"
    # Raw milled rice is ~350-370 kcal/100g dry weight (USDA reference:
    # ~365 kcal/100g) — this is the spot-check documented in
    # scripts/import_ifct.py's module docstring that established `enerc` is
    # kJ, not kcal. Asserting the range here turns that one-time manual
    # check into a standing regression test: if a future CSV revision
    # changes units without anyone noticing, this fails loudly instead of
    # silently importing energy values off by a factor of ~4.
    assert 300 < float(rice.energy_kcal) < 400
    assert 70 < float(rice.available_carb_g) < 85

    await engine.dispose()


@pytest.mark.skipif(not REAL_CSV.exists(), reason="ifct2017_compositions.csv not present")
async def test_import_is_idempotent_on_rerun():
    engine, session_factory = await build_sqlite_db()
    async with session_factory() as session:
        await import_csv(session, REAL_CSV)
        first_stats = await import_csv(session, REAL_CSV)  # re-run, same file

    async with session_factory() as session:
        result = await session.execute(select(IFCTFood))
        rows = result.scalars().all()

    # Upserted on `code`, not duplicated: row count matches one import's
    # worth, not two.
    assert len(rows) == first_stats.imported

    await engine.dispose()
