CREATE TABLE meal_logs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID REFERENCES users(id),
    meal_time               TIMESTAMPTZ NOT NULL,

    -- Food identification
    food_items              JSONB NOT NULL,     -- full enriched item list
    recognition_confidence  NUMERIC(3,2),
    user_corrected          BOOLEAN DEFAULT false,
    user_correction_notes   TEXT,

    -- Nutritional totals
    total_calories          INTEGER,
    total_carbs_g           NUMERIC(6,1),
    total_protein_g         NUMERIC(6,1),
    total_fat_g             NUMERIC(6,1),
    glycaemic_load          NUMERIC(5,1),

    -- Bolus recommendation (FK to audit log)
    recommendation_id       UUID REFERENCES recommendation_audit_log(id),

    -- Post-meal outcome (filled in later from CGM data)
    post_meal_glucose_1hr   INTEGER,    -- mg/dL at t+1hr
    post_meal_glucose_2hr   INTEGER,    -- mg/dL at t+2hr
    glucose_outcome         TEXT,       -- 'IN_RANGE' | 'HIGH' | 'LOW'

    created_at              TIMESTAMPTZ DEFAULT now()
);
