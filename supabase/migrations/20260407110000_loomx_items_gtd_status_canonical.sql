-- Migration: align loomx_items.gtd_status check constraint to AGENT-STANDARD §5
-- Date: 2026-04-07
-- Trigger: GTD c8e7da72 — DB rejected `in_progress` UPDATE because the check
-- constraint did not include it. Also `waiting_for`/`calendar`/`project_task`
-- are out of sync with the Board MCP enum and AGENT-STANDARD canonical states.
--
-- Canonical states (AGENT-STANDARD §5):
--   inbox, next_action, waiting, scheduled, in_progress, someday, done, trash
--
-- Data migration:
--   waiting_for  -> waiting
--   calendar     -> scheduled
--   project_task -> next_action   (project_task is not canonical; collapse)

BEGIN;

-- 1) Drop the old check constraint (named by Postgres convention)
ALTER TABLE loomx_items
  DROP CONSTRAINT IF EXISTS loomx_items_gtd_status_check;

-- 2) Migrate existing rows to canonical values
UPDATE loomx_items SET gtd_status = 'waiting'      WHERE gtd_status = 'waiting_for';
UPDATE loomx_items SET gtd_status = 'scheduled'    WHERE gtd_status = 'calendar';
UPDATE loomx_items SET gtd_status = 'next_action'  WHERE gtd_status = 'project_task';

-- 3) Recreate the check constraint with the canonical set
ALTER TABLE loomx_items
  ADD CONSTRAINT loomx_items_gtd_status_check
  CHECK (gtd_status IN (
    'inbox',
    'next_action',
    'waiting',
    'scheduled',
    'in_progress',
    'someday',
    'done',
    'trash'
  ));

-- 4) Realign the waiting view (was filtering by 'waiting_for')
--    Other views (loomx_v_inbox, loomx_v_next_actions, loomx_v_project_dashboard)
--    keep working unchanged.
CREATE OR REPLACE VIEW loomx_v_waiting_for AS
SELECT i.*, array_agg(ip.project_id) AS project_ids
FROM loomx_items i
LEFT JOIN loomx_item_projects ip ON i.id = ip.item_id
WHERE i.gtd_status = 'waiting'
GROUP BY i.id
ORDER BY i.deadline NULLS LAST;

COMMIT;
