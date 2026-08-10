-- 014_ifct_foods.sql
-- Indian Food Composition Tables 2017 (IFCT2017), diabetes-relevant columns
-- only. The source CSV (backend/ifct2017_compositions.csv) has ~250 columns
-- per food (every micronutrient/phytochemical IFCT tracks); we keep the six
-- that feed carb counting and glycaemic load: available carbohydrate,
-- protein, fat, fibre, energy, and sugars. Everything else is dropped at
-- import time, not stored and re-filtered later.
--
-- Values are per 100g, matching how USDA data and the existing meal-logging
-- code (nutrition.py's `*_per_100g` fields) already represent nutrition —
-- one unit convention throughout the nutrition-source chain.
--
-- Energy unit: IFCT2017's `enerc` column is kilojoules, not kilocalories
-- (spot-checked at import time against known references — see
-- scripts/import_ifct.py for the verification). This table stores the
-- already-converted kcal value so nothing downstream has to know or care.

CREATE TABLE IF NOT EXISTS ifct_foods (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code              TEXT NOT NULL UNIQUE,   -- IFCT2017 food code, e.g. 'A015'
    name              TEXT NOT NULL,          -- e.g. 'Rice, raw, milled'
    energy_kcal       NUMERIC(7,1) NOT NULL,  -- per 100g, converted from enerc (kJ) / 4.184
    available_carb_g  NUMERIC(6,2) NOT NULL,  -- per 100g, from choavldf
    protein_g         NUMERIC(6,2) NOT NULL,  -- per 100g, from protcnt
    fat_g             NUMERIC(6,2) NOT NULL,  -- per 100g, from fatce
    fibre_g           NUMERIC(6,2) NOT NULL,  -- per 100g, from fibtg
    sugars_g          NUMERIC(6,2) NOT NULL,  -- per 100g, from fsugar
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Fuzzy name search ("dosa" -> "Dosa, plain", partial/misspelled queries).
-- pg_trgm's GIN index is what makes `similarity(name, query)` fast instead
-- of a sequential scan; the search code (services/nutrition/source_router.py)
-- falls back to a plain ILIKE substring match on dialects without pg_trgm
-- (sqlite, in tests), which needs no index of its own.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS ifct_foods_name_trgm_idx
  ON ifct_foods USING GIN (name gin_trgm_ops);
