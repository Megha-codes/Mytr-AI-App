-- Migration 005: Add fiber column to meal_logs
-- Required for USDA FoodData Central nutrition tracking

ALTER TABLE meal_logs
    ADD COLUMN IF NOT EXISTS total_fiber_g NUMERIC(6,1) DEFAULT 0;
