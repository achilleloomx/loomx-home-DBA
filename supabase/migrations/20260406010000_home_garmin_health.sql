-- Migration: home_garmin_health table
-- Date: 2026-04-06
-- Namespace: home_* (personal health data, scope: LoomX Home only)
-- Requested by: Loomy for Evaristo

CREATE TABLE IF NOT EXISTS home_garmin_health (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL UNIQUE,

  -- Sleep
  sleep_seconds INT,
  deep_sleep_seconds INT,
  light_sleep_seconds INT,
  rem_sleep_seconds INT,
  awake_seconds INT,
  sleep_score INT,

  -- Activity
  total_steps INT,
  active_calories INT,
  total_calories INT,
  distance_meters INT,

  -- Heart
  resting_hr INT,
  min_hr INT,
  max_hr INT,

  -- Body Battery
  body_battery_start INT,
  body_battery_end INT,
  body_battery_charged INT,
  body_battery_drained INT,

  -- Stress
  avg_stress INT,
  max_stress INT,

  -- Blood Pressure
  systolic INT,
  diastolic INT,
  pulse INT,

  -- Meta
  raw_json JSONB,           -- full API response for future fields
  fetched_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE home_garmin_health ENABLE ROW LEVEL SECURITY;
-- Deny all by default, service_role only (same pattern as other tables)

COMMENT ON TABLE home_garmin_health IS 'Daily Garmin health metrics synced from Vivosmart 5 via python-garminconnect';
