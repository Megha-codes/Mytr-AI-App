"""One-time (re-runnable) import of IFCT2017 into the `ifct_foods` table
(migrations/014_ifct_foods.sql). Diabetes-relevant columns only — the source
CSV has ~250 columns per food (every micronutrient IFCT tracks); we keep six.

Usage (from backend/):
    python scripts/import_ifct.py [--csv path/to/ifct2017_compositions.csv]

Re-running is safe: rows are upserted on `code`, so a repeat import (e.g.
after IFCT publishes a corrected CSV) updates existing rows instead of
duplicating them.

── Energy unit verification ───────────────────────────────────────────────
IFCT2017's `enerc` column is NOT documented as kcal or kJ in the CSV header
itself, so this was spot-checked against a known reference before trusting
it, per the standard IFCT2017 field dictionary (energy is reported in kJ,
with a parallel kcal column in some IFCT distributions that this particular
export doesn't include):

    Row A015 "Rice, raw, milled": enerc = 1491
    USDA FoodData Central "Rice, white, long-grain, regular, raw,
    unenriched" (a close match for the same food): ~365 kcal/100g.

    1491 / 4.184 = 356.4 kcal/100g  <- within ~2.5% of the USDA reference.
    1491 kcal/100g on its own would be physically implausible (no whole
    food gets close to that; pure fat, the densest macronutrient, tops out
    around 884 kcal/100g) — so kJ is the only value that makes sense here.

    => enerc is kilojoules. CONVERT_FACTOR below (/ 4.184) is applied to
    every row at import time; `ifct_foods.energy_kcal` is already-converted
    kcal, so nothing downstream needs to know this.

Note for whoever wires the "prove IFCT resolves dosa" demo step: this CSV is
IFCT2017's raw/single-ingredient composition table (542 rows) — rice,
lentils, vegetables, meats, etc. — not IFCT's separate prepared-dish/recipe
table. There is no "Dosa", "Idli", "Chapati", etc. entry in this file at
all, confirmed by exhaustive substring search over every row's `name`
column. A search for a prepared dish like "dosa" is expected to correctly
report zero IFCT results and fall through to USDA/Gemini — that's the
source router working as designed, not a bug. IFCT hits are expected for
its actual contents: raw ingredients like "rice", "banana", "toor dal".
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import logging
import os
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path

# Running this file directly (`python scripts/import_ifct.py`) only puts
# scripts/ itself on sys.path, not backend/ — needed for `from app...`
# below. Running via `python -m scripts.import_ifct` from backend/ doesn't
# need this, but adding it unconditionally makes both invocations work.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

logger = logging.getLogger("mytr.import_ifct")

# IFCT2017 `enerc` -> kcal. See module docstring for the spot-check that
# established this is kJ, not kcal.
KJ_PER_KCAL = 4.184

DEFAULT_CSV_PATH = Path(__file__).resolve().parent.parent / "ifct2017_compositions.csv"

# Output column -> (source CSV column, decimal places to round to)
_FIELD_MAP = {
    "available_carb_g": ("choavldf", 2),
    "protein_g": ("protcnt", 2),
    "fat_g": ("fatce", 2),
    "fibre_g": ("fibtg", 2),
    "sugars_g": ("fsugar", 2),
}


@dataclass
class ImportStats:
    total_rows: int
    imported: int
    skipped: int


def _to_float(value: str | None) -> float:
    if value is None:
        return 0.0
    value = value.strip()
    if not value:
        return 0.0
    try:
        return float(value)
    except ValueError:
        return 0.0


def parse_row(row: dict) -> dict | None:
    """Maps one raw CSV row to an `ifct_foods` row dict, or None if the row
    is missing the two fields we can't sensibly default (code/name)."""
    code = (row.get("code") or "").strip()
    name = (row.get("name") or "").strip()
    if not code or not name:
        return None

    parsed = {"code": code, "name": name}
    for out_field, (src_field, decimals) in _FIELD_MAP.items():
        parsed[out_field] = round(_to_float(row.get(src_field)), decimals)

    parsed["energy_kcal"] = round(_to_float(row.get("enerc")) / KJ_PER_KCAL, 1)
    return parsed


def parse_csv(csv_path: Path) -> tuple[list[dict], int]:
    """Returns (parsed_rows, skipped_count)."""
    rows: list[dict] = []
    skipped = 0
    # utf-8-sig: the CSV starts with a BOM (`﻿` before the `code`
    # header) — plain utf-8 would leave that attached to the first column
    # name and silently break every `row.get("code")` lookup above.
    with open(csv_path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for raw_row in reader:
            parsed = parse_row(raw_row)
            if parsed is None:
                skipped += 1
                continue
            rows.append(parsed)
    return rows, skipped


async def import_csv(session, csv_path: Path = DEFAULT_CSV_PATH) -> ImportStats:
    """Upserts every row of `csv_path` into `ifct_foods`, keyed on `code`.
    Takes an open AsyncSession rather than owning its own engine, so tests
    can point this at an in-memory sqlite session."""
    from sqlalchemy.dialects import postgresql, sqlite

    from app.models.ifct_food import IFCTFood

    rows, skipped = parse_csv(csv_path)
    if not rows:
        return ImportStats(total_rows=0, imported=0, skipped=skipped)

    insert = sqlite.insert if session.bind.dialect.name == "sqlite" else postgresql.insert
    for row in rows:
        row["id"] = str(uuid.uuid4())

    stmt = insert(IFCTFood).values(rows)
    update_cols = {k: getattr(stmt.excluded, k) for k in _FIELD_MAP} | {
        "name": stmt.excluded.name,
        "energy_kcal": stmt.excluded.energy_kcal,
    }
    stmt = stmt.on_conflict_do_update(index_elements=["code"], set_=update_cols)
    await session.execute(stmt)
    await session.commit()

    return ImportStats(total_rows=len(rows) + skipped, imported=len(rows), skipped=skipped)


async def _main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV_PATH)
    args = parser.parse_args()

    if not args.csv.exists():
        print(f"CSV not found: {args.csv}", file=sys.stderr)
        sys.exit(1)

    # Imported lazily so `parse_row`/`parse_csv` stay importable (for unit
    # tests) without requiring DATABASE_URL to be set at all.
    from app.database import AsyncSessionLocal

    async with AsyncSessionLocal() as session:
        stats = await import_csv(session, args.csv)

    print(
        f"Imported {stats.imported} foods from {args.csv.name} "
        f"({stats.skipped} skipped, missing code/name)."
    )


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(_main())
