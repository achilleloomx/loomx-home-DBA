-- 20260409100000_gtd_ui_sprint1.sql
-- GTD UI Sprint 1 — schema extensions for the PWA GTD interface.
--
-- Trigger: board msgs 35c25726 (Loomy) + 18043d4b (app), 2026-04-09.
-- Decision: D-024 (this migration).
--
-- Summary of changes:
--   1. loomx_owner_auth     — mapping owner slug <-> auth.uid() + PMO flag
--   2. loomx_get_owner_slug / loomx_is_pmo  — SECURITY DEFINER helpers for RLS
--   3. loomx_gtd_projects   — GTD projects (separate from org loomx_projects)
--   4. loomx_contexts       — custom GTD contexts per owner
--   5. ALTER loomx_items     — 6 new columns (context, time_estimate, energy_level,
--                              deleted_at, clarified_at, project_id)
--   6. RLS policies for authenticated (PWA users)
--   7. Indexes
--   8. Seed data
--
-- Design rationale — GTD projects vs loomx_projects:
--   loomx_projects is the org/anagrafica registry (client_id, repo, local_path,
--   type consulting/tech/internal). GTD projects are personal productivity
--   outcomes (title, owner, active/completed/on_hold/dropped). Mixing them
--   would pollute the anagrafica with hundreds of small personal "projects"
--   and force incompatible status enums to coexist. The existing N:N
--   loomx_item_projects links items to org projects; the new project_id FK
--   on loomx_items links to GTD projects (1:N — an item belongs to at most
--   one GTD project).

BEGIN;

-- ============================================================
-- 1. loomx_owner_auth — mapping owner slug <-> auth.uid()
-- ============================================================
-- Used by RLS policies to bridge Supabase Auth UUIDs with the slug-based
-- ownership model of loomx_items. Agents have user_id = NULL (they access
-- via service_role or dedicated Postgres roles, not Supabase Auth).

CREATE TABLE loomx_owner_auth (
  owner_slug  TEXT PRIMARY KEY,
  user_id     UUID UNIQUE,              -- auth.users.id; NULL for agents
  is_pmo      BOOLEAN NOT NULL DEFAULT false,  -- PMO: SELECT all items cross-owner
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE loomx_owner_auth ENABLE ROW LEVEL SECURITY;

-- Allow each authenticated user to read their own mapping row (useful for the app
-- to know the current user's slug). No INSERT/UPDATE/DELETE for authenticated.
CREATE POLICY loomx_owner_auth_select_own
  ON loomx_owner_auth FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- 2. RLS helper functions (SECURITY DEFINER)
-- ============================================================

CREATE OR REPLACE FUNCTION loomx_get_owner_slug()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT owner_slug FROM loomx_owner_auth WHERE user_id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION loomx_is_pmo()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT is_pmo FROM loomx_owner_auth WHERE user_id = auth.uid()),
    false
  )
$$;

-- ============================================================
-- 3. loomx_gtd_projects — GTD projects (outcome multi-step)
-- ============================================================
-- NOT the same as loomx_projects (org/anagrafica). See design rationale above.
-- A GTD project is "stalled" when it has no associated next_action item —
-- the app/weekly review detects this via query, not a DB trigger.

CREATE TABLE loomx_gtd_projects (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL,
  description TEXT,
  owner       TEXT NOT NULL,              -- slug: 'achille', 'loomy', etc.
  status      TEXT NOT NULL DEFAULT 'active'
              CHECK (status IN ('active', 'completed', 'on_hold', 'dropped')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE loomx_gtd_projects ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. loomx_contexts — custom GTD contexts per owner
-- ============================================================
-- The context value on loomx_items is free text (no FK). This table
-- provides the dropdown catalog per owner. Deleting a context here
-- does NOT null-out items that reference it — the UI handles stale values.

CREATE TABLE loomx_contexts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,              -- e.g. '@casa', '@palestra'
  owner       TEXT NOT NULL,              -- slug
  is_default  BOOLEAN NOT NULL DEFAULT false,
  sort_order  SMALLINT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_loomx_contexts_owner_name
  ON loomx_contexts(owner, name);

ALTER TABLE loomx_contexts ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 5. ALTER loomx_items — 6 new columns for GTD UI
-- ============================================================

ALTER TABLE loomx_items
  ADD COLUMN context       TEXT,
  ADD COLUMN time_estimate SMALLINT,
  ADD COLUMN energy_level  SMALLINT,
  ADD COLUMN deleted_at    TIMESTAMPTZ,
  ADD COLUMN clarified_at  TIMESTAMPTZ,
  ADD COLUMN project_id    UUID REFERENCES loomx_gtd_projects(id) ON DELETE SET NULL;

-- Constraints
ALTER TABLE loomx_items
  ADD CONSTRAINT loomx_items_time_estimate_check
  CHECK (time_estimate IS NULL OR time_estimate IN (5, 15, 30, 60, 120));

ALTER TABLE loomx_items
  ADD CONSTRAINT loomx_items_energy_level_check
  CHECK (energy_level IS NULL OR energy_level BETWEEN 1 AND 3);

-- ============================================================
-- 6. RLS policies for authenticated role (PWA users)
-- ============================================================
-- These policies are ADDITIVE to existing per-agent policies
-- (e.g. doc_researcher policies from 20260407100000). Different
-- roles, no conflict.

-- 6a. loomx_items — SELECT: PMO sees everything, others see own items
CREATE POLICY loomx_items_select_authenticated
  ON loomx_items FOR SELECT TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
  );

-- 6b. loomx_items — INSERT: own items only
CREATE POLICY loomx_items_insert_authenticated
  ON loomx_items FOR INSERT TO authenticated
  WITH CHECK (owner = loomx_get_owner_slug());

-- 6c. loomx_items — UPDATE: own items only
CREATE POLICY loomx_items_update_authenticated
  ON loomx_items FOR UPDATE TO authenticated
  USING (owner = loomx_get_owner_slug())
  WITH CHECK (owner = loomx_get_owner_slug());

-- 6d. loomx_items — DELETE: own items only (hard-delete within undo window)
CREATE POLICY loomx_items_delete_authenticated
  ON loomx_items FOR DELETE TO authenticated
  USING (owner = loomx_get_owner_slug());

-- 6e. loomx_gtd_projects — SELECT: PMO sees all, others see own
CREATE POLICY loomx_gtd_projects_select_authenticated
  ON loomx_gtd_projects FOR SELECT TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
  );

-- 6f. loomx_gtd_projects — INSERT: own only
CREATE POLICY loomx_gtd_projects_insert_authenticated
  ON loomx_gtd_projects FOR INSERT TO authenticated
  WITH CHECK (owner = loomx_get_owner_slug());

-- 6g. loomx_gtd_projects — UPDATE: own only
CREATE POLICY loomx_gtd_projects_update_authenticated
  ON loomx_gtd_projects FOR UPDATE TO authenticated
  USING (owner = loomx_get_owner_slug())
  WITH CHECK (owner = loomx_get_owner_slug());

-- 6h. loomx_gtd_projects — DELETE: own only
CREATE POLICY loomx_gtd_projects_delete_authenticated
  ON loomx_gtd_projects FOR DELETE TO authenticated
  USING (owner = loomx_get_owner_slug());

-- 6i. loomx_contexts — full CRUD on own contexts
CREATE POLICY loomx_contexts_select_authenticated
  ON loomx_contexts FOR SELECT TO authenticated
  USING (owner = loomx_get_owner_slug());

CREATE POLICY loomx_contexts_insert_authenticated
  ON loomx_contexts FOR INSERT TO authenticated
  WITH CHECK (owner = loomx_get_owner_slug());

CREATE POLICY loomx_contexts_update_authenticated
  ON loomx_contexts FOR UPDATE TO authenticated
  USING (owner = loomx_get_owner_slug())
  WITH CHECK (owner = loomx_get_owner_slug());

CREATE POLICY loomx_contexts_delete_authenticated
  ON loomx_contexts FOR DELETE TO authenticated
  USING (owner = loomx_get_owner_slug());

-- 6j. loomx_item_projects — SELECT for authenticated (weekly review needs org project links)
CREATE POLICY loomx_item_projects_select_authenticated
  ON loomx_item_projects FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM loomx_items i
      WHERE i.id = loomx_item_projects.item_id
        AND (loomx_is_pmo() OR i.owner = loomx_get_owner_slug())
    )
  );

-- 6k. loomx_projects (org) — read-only for PMO (weekly review cross-project view)
CREATE POLICY loomx_projects_select_pmo
  ON loomx_projects FOR SELECT TO authenticated
  USING (loomx_is_pmo());

-- ============================================================
-- 7. Indexes
-- ============================================================

-- Engage view: filter by owner + status (+ optional context/energy/time in WHERE)
CREATE INDEX idx_loomx_items_owner_status
  ON loomx_items(owner, gtd_status);

-- Observatory: all items by status
CREATE INDEX idx_loomx_items_status
  ON loomx_items(gtd_status);

-- Waiting view: items where someone is waiting
CREATE INDEX idx_loomx_items_waiting_on
  ON loomx_items(waiting_on)
  WHERE waiting_on IS NOT NULL;

-- Soft-delete cleanup cron
CREATE INDEX idx_loomx_items_deleted_at
  ON loomx_items(deleted_at)
  WHERE deleted_at IS NOT NULL;

-- GTD project items
CREATE INDEX idx_loomx_items_project_id
  ON loomx_items(project_id)
  WHERE project_id IS NOT NULL;

-- Contexts lookup
CREATE INDEX idx_loomx_contexts_owner
  ON loomx_contexts(owner);

-- GTD projects by owner + status
CREATE INDEX idx_loomx_gtd_projects_owner_status
  ON loomx_gtd_projects(owner, status);

-- ============================================================
-- 8. Seed data
-- ============================================================

-- 8a. Owner-auth mapping. Achille is PMO. Agents have NULL user_id.
-- Achille's auth UUID is auto-detected from auth.users (first non-system user).
INSERT INTO loomx_owner_auth (owner_slug, user_id, is_pmo) VALUES
  ('achille', NULL, true),
  ('loomy',   NULL, false),
  ('dba',     NULL, false),
  ('app',     NULL, false),
  ('assistant', NULL, false);

-- Auto-populate Achille's auth UUID
DO $$
DECLARE
  v_uid uuid;
  v_email text;
BEGIN
  SELECT id, email INTO v_uid, v_email
  FROM auth.users
  WHERE email NOT LIKE '%@loomx.local'
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_uid IS NOT NULL THEN
    UPDATE loomx_owner_auth SET user_id = v_uid WHERE owner_slug = 'achille';
    RAISE NOTICE 'loomx_owner_auth: mapped achille -> % (%)', v_uid, v_email;
  ELSE
    RAISE WARNING 'loomx_owner_auth: no non-system auth user found. '
      'Populate manually: UPDATE loomx_owner_auth SET user_id = ''<uuid>'' '
      'WHERE owner_slug = ''achille'';';
  END IF;
END $$;

-- 8b. Default GTD contexts for Achille (deletable by user)
INSERT INTO loomx_contexts (name, owner, is_default, sort_order) VALUES
  ('@casa',        'achille', true, 1),
  ('@ufficio',     'achille', true, 2),
  ('@telefono',    'achille', true, 3),
  ('@computer',    'achille', true, 4),
  ('@commissioni', 'achille', true, 5);

COMMIT;
