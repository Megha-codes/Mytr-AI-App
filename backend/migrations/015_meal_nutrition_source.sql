-- 015_meal_nutrition_source.sql
-- Records which of the three nutrition sources (services/nutrition/
-- source_router.py) a logged meal's macros came from, and whether that
-- source is a real database lookup or a guess.

ALTER TABLE meal_logs
    ADD COLUMN IF NOT EXISTS nutrition_source TEXT;
    -- 'ifct' | 'usda' | 'gemini_estimate' | 'manual' (user-entered totals,
    -- POST /nutrition/log — not resolved through the source router at all)

ALTER TABLE meal_logs
    ADD COLUMN IF NOT EXISTS nutrition_verified BOOLEAN;
    -- true for 'ifct'/'usda'/'manual' (a real lookup or the user's own
    -- number); false for 'gemini_estimate' (a guess). NULL on rows logged
    -- before this migration — genuinely unknown, not false.
