-- Migration: RLS policies for garmin-sync dedicated user on home_garmin_health
-- Date: 2026-04-06
-- Namespace: home_*
-- Decision: D-009
-- Requested by: Loomy (001) for garmin_fetch.py script
--
-- NOTE: The auth user garmin-sync@loomx.local must be created via Supabase
-- Admin API BEFORE this migration is applied. See docs/DECISIONS.md D-009.
-- The user creation cannot be done reliably in a SQL migration because
-- Supabase auth schema has internal triggers and functions that must run.

-- Policy: allow SELECT on own data (needed for upsert conflict detection)
CREATE POLICY garmin_sync_select ON home_garmin_health
  FOR SELECT
  TO authenticated
  USING (auth.jwt() ->> 'email' = 'garmin-sync@loomx.local');

-- Policy: allow INSERT
CREATE POLICY garmin_sync_insert ON home_garmin_health
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'garmin-sync@loomx.local');

-- Policy: allow UPDATE
CREATE POLICY garmin_sync_update ON home_garmin_health
  FOR UPDATE
  TO authenticated
  USING (auth.jwt() ->> 'email' = 'garmin-sync@loomx.local')
  WITH CHECK (auth.jwt() ->> 'email' = 'garmin-sync@loomx.local');

-- No DELETE policy: deny by default (RLS deny-all pattern)
-- No policies on any other table: this user has zero access elsewhere

COMMENT ON POLICY garmin_sync_select ON home_garmin_health IS 'Allow garmin-sync user to read health data (needed for upsert)';
COMMENT ON POLICY garmin_sync_insert ON home_garmin_health IS 'Allow garmin-sync user to insert health data';
COMMENT ON POLICY garmin_sync_update ON home_garmin_health IS 'Allow garmin-sync user to update health data';
