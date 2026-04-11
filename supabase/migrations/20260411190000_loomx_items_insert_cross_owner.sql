-- 20260411190000_loomx_items_insert_cross_owner.sql
-- GTD Capture cross-owner — extend INSERT policy on loomx_items.
--
-- Trigger: app session 2026-04-11, board msg 781df652 (app → dba). The "Capture
-- con Destinatario" feature lets the user pick the target owner of a new GTD
-- item (self / loomy / assistant for non-PMO, any slug for PMO). Today the
-- INSERT policy (created in 20260409100000_gtd_ui_sprint1.sql, line 153) only
-- allows owner = loomx_get_owner_slug(), so any cross-owner capture is blocked
-- by RLS.
--
-- Decision: amendment to D-024 — INSERT gets the same PMO override as
-- SELECT/UPDATE/DELETE (extended in 20260411100000), and a hardcoded whitelist
-- for non-PMO users targeting the dispatcher slugs (loomy, assistant).
--
-- App agent proposed two options (whitelist literal vs new column
-- can_be_target_by_anyone in loomx_owner_auth). Decision: option A (literal
-- whitelist) — only two dispatchers exist today, the rule is small enough to
-- live in the policy, and adding a new column would also require backfill +
-- security review for a use case that does not yet exist. Revisit if a third
-- dispatcher slug appears (then promote to a column or a SECURITY DEFINER
-- helper).
--
-- Threat model: Vanessa (non-PMO) can now write items whose owner is 'loomy'
-- or 'assistant'. This is intentional — both are agent inboxes, not user
-- inboxes, and Loomy/Evaristo already process items pushed by humans via
-- other channels. She still cannot write items targeting 'achille' or any
-- other human owner (RLS denies it).
--
-- Scope: only loomx_items INSERT. UPDATE/DELETE keep the 20260411100000 rules
-- (PMO override OR own items): once an item is written to a dispatcher inbox,
-- the author cannot edit/delete it — only the target owner (or PMO) can.

BEGIN;

DROP POLICY IF EXISTS loomx_items_insert_authenticated ON loomx_items;
CREATE POLICY loomx_items_insert_authenticated
  ON loomx_items FOR INSERT TO authenticated
  WITH CHECK (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
    OR owner IN ('loomy', 'assistant')
  );

COMMIT;
