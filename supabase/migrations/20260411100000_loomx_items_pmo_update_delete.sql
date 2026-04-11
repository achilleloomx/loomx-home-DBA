-- 20260411100000_loomx_items_pmo_update_delete.sql
-- GTD UI Sprint 1 hotfix — extend PMO write privileges on loomx_items + loomx_gtd_projects.
--
-- Trigger: app session 2026-04-11 — feature "inline editing GTD cartine" needs Achille
-- (PMO) to UPDATE owner/priority/gtd_status of any item, and to soft-delete any item
-- (UPDATE deleted_at). The original GTD UI Sprint 1 migration (20260409100000) only
-- granted PMO read-all; write was restricted to own items, blocking the feature.
--
-- Decision: D-024 amendment — PMO write override is symmetrical to PMO read override.
-- Threat model: PMO is a single trusted user (Achille) who is the org owner. Granting
-- him write across all owners is consistent with his role. Vanessa (future non-PMO
-- authenticated user) is unaffected: she stays restricted to her own items.
--
-- Scope:
--   - loomx_items: UPDATE + DELETE policies extended with PMO override
--   - loomx_gtd_projects: UPDATE + DELETE policies extended with PMO override
--   - INSERT policies untouched: PMO inserts only as himself (owner = his slug)

BEGIN;

-- ============================================================
-- loomx_items
-- ============================================================

DROP POLICY IF EXISTS loomx_items_update_authenticated ON loomx_items;
CREATE POLICY loomx_items_update_authenticated
  ON loomx_items FOR UPDATE TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
  )
  WITH CHECK (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
  );

DROP POLICY IF EXISTS loomx_items_delete_authenticated ON loomx_items;
CREATE POLICY loomx_items_delete_authenticated
  ON loomx_items FOR DELETE TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
  );

-- ============================================================
-- loomx_gtd_projects
-- ============================================================

DROP POLICY IF EXISTS loomx_gtd_projects_update_authenticated ON loomx_gtd_projects;
CREATE POLICY loomx_gtd_projects_update_authenticated
  ON loomx_gtd_projects FOR UPDATE TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
  )
  WITH CHECK (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
  );

DROP POLICY IF EXISTS loomx_gtd_projects_delete_authenticated ON loomx_gtd_projects;
CREATE POLICY loomx_gtd_projects_delete_authenticated
  ON loomx_gtd_projects FOR DELETE TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
  );

COMMIT;
