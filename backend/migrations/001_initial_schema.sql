-- 001_initial_schema.sql
-- Migration for MetaSync core onboarding tables

-- Enable pgcrypto for gen_random_uuid() if not already available (depends on Postgres version)
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Table 1: users
CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email               TEXT UNIQUE NOT NULL,
    password_hash       TEXT NOT NULL,
    name                TEXT,
    dob                 DATE,
    gender              TEXT,
    weight_kg           NUMERIC(5,2),
    height_cm           NUMERIC(5,2),
    diabetes_type       TEXT CHECK (diabetes_type IN ('T1', 'T2', 'PRE')),
    created_at          TIMESTAMPTZ DEFAULT now(),
    consent_confirmed_at TIMESTAMPTZ
);

-- Table 2: insulin_profiles
CREATE TABLE insulin_profiles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES users(id) ON DELETE CASCADE,
    icr                 NUMERIC(5,2),      -- grams of carb per 1 unit
    isf                 NUMERIC(6,2),      -- mg/dL drop per 1 unit
    basal_rate          NUMERIC(5,3),      -- units/hr, T1 only
    target_glucose_min  INTEGER,           -- mg/dL
    target_glucose_max  INTEGER,           -- mg/dL
    insulin_type        TEXT,
    profile_complete    BOOLEAN DEFAULT false,
    created_at          TIMESTAMPTZ DEFAULT now(),
    updated_at          TIMESTAMPTZ DEFAULT now()
);

-- Table 3: cgm_devices
-- NOTE: CGM credentials (OAuth tokens, LibreLinkUp passwords) are NEVER stored in this table. 
-- They are managed securely via AWS Secrets Manager. This table only holds active device metadata.
CREATE TABLE cgm_devices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    device_type     TEXT CHECK (device_type IN (
                        'LIBRE_2', 'LIBRE_3', 'MANUAL'
                    )),
    is_active       BOOLEAN DEFAULT true,
    connected_at    TIMESTAMPTZ DEFAULT now()
);

-- Table 4: lifestyle_baselines
CREATE TABLE lifestyle_baselines (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID REFERENCES users(id) ON DELETE CASCADE,
    baseline_sleep_hrs      NUMERIC(3,1),
    baseline_activity_level TEXT CHECK (baseline_activity_level IN (
                                'SEDENTARY', 'LIGHT', 'MODERATE', 'ACTIVE'
                            )),
    baseline_stress_level   TEXT CHECK (baseline_stress_level IN (
                                'LOW', 'MODERATE', 'HIGH'
                            )),
    baseline_calories       INTEGER,
    recorded_at             TIMESTAMPTZ DEFAULT now()
);

-- Table 5: recommendation_audit_log
CREATE TABLE recommendation_audit_log (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID REFERENCES users(id),
    recommended_dose_units  NUMERIC(5,2),
    base_bolus              NUMERIC(5,2),
    correction_dose         NUMERIC(5,2),
    lifestyle_adjustment_pct NUMERIC(5,1),
    confidence_score        NUMERIC(3,2),
    feature_vector          JSONB,          -- full snapshot of all inputs
    model_version           TEXT,
    recommendation_drivers  TEXT[],
    show_doctor_flag        BOOLEAN,
    created_at              TIMESTAMPTZ DEFAULT now()
);
