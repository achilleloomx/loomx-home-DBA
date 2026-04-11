-- 20260411160000_loomx_item_agents_raci_recursion_fix.sql
-- Hotfix per 20260411150000 — le policy authenticated andavano in recursion infinita.
--
-- Sintomo (verificato in test S018):
--   ERROR 42P17: infinite recursion detected in policy for relation "loomx_items"
--
-- Causa: la policy `loomx_items_select_authenticated` aveva una EXISTS su
-- `loomx_item_agents`, che a sua volta ha una policy `loomx_item_agents_select_authenticated`
-- che fa EXISTS su `loomx_items`. Postgres rifiuta il loop.
--
-- Fix: sostituire le sub-EXISTS con due funzioni SECURITY DEFINER che bypassano RLS:
--   - `loomx_item_owner(uuid)`            → owner slug dell'item
--   - `loomx_user_engaged_role(uuid)`     → role del current user su item, NULL se nessuno
--
-- Le policy ora chiamano queste funzioni, eliminando il riferimento incrociato a livello
-- di policy.

BEGIN;

-- ============================================================
-- Helper SECURITY DEFINER functions
-- ============================================================

CREATE OR REPLACE FUNCTION public.loomx_item_owner(p_item_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT owner FROM loomx_items WHERE id = p_item_id
$$;

COMMENT ON FUNCTION public.loomx_item_owner(uuid) IS
  'SECURITY DEFINER lookup dell''owner di un item GTD; bypassa RLS per evitare loop nelle policy.';

CREATE OR REPLACE FUNCTION public.loomx_user_engaged_role(p_item_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT role FROM loomx_item_agents
   WHERE item_id = p_item_id
     AND agent_slug = (
       SELECT owner_slug FROM loomx_owner_auth WHERE user_id = auth.uid()
     )
$$;

COMMENT ON FUNCTION public.loomx_user_engaged_role(uuid) IS
  'SECURITY DEFINER: ritorna il role (collaborator|watcher|NULL) con cui l''utente '
  'corrente è linkato all''item via loomx_item_agents. Bypassa RLS.';

GRANT EXECUTE ON FUNCTION public.loomx_item_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.loomx_user_engaged_role(uuid) TO authenticated;

-- ============================================================
-- Riscrittura policy loomx_items
-- ============================================================

DROP POLICY IF EXISTS loomx_items_select_authenticated ON loomx_items;
CREATE POLICY loomx_items_select_authenticated
  ON loomx_items FOR SELECT
  TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
    OR loomx_user_engaged_role(id) IS NOT NULL
  );

DROP POLICY IF EXISTS loomx_items_update_authenticated ON loomx_items;
CREATE POLICY loomx_items_update_authenticated
  ON loomx_items FOR UPDATE
  TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
    OR loomx_user_engaged_role(id) = 'collaborator'
  )
  WITH CHECK (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
    OR loomx_user_engaged_role(id) = 'collaborator'
  );

-- ============================================================
-- Riscrittura policy loomx_item_agents
-- ============================================================

DROP POLICY IF EXISTS loomx_item_agents_select_authenticated ON loomx_item_agents;
CREATE POLICY loomx_item_agents_select_authenticated
  ON loomx_item_agents FOR SELECT
  TO authenticated
  USING (
    loomx_is_pmo()
    OR agent_slug = loomx_get_owner_slug()
    OR loomx_item_owner(item_id) = loomx_get_owner_slug()
  );

DROP POLICY IF EXISTS loomx_item_agents_insert_authenticated ON loomx_item_agents;
CREATE POLICY loomx_item_agents_insert_authenticated
  ON loomx_item_agents FOR INSERT
  TO authenticated
  WITH CHECK (
    loomx_is_pmo()
    OR loomx_item_owner(item_id) = loomx_get_owner_slug()
  );

DROP POLICY IF EXISTS loomx_item_agents_delete_authenticated ON loomx_item_agents;
CREATE POLICY loomx_item_agents_delete_authenticated
  ON loomx_item_agents FOR DELETE
  TO authenticated
  USING (
    loomx_is_pmo()
    OR loomx_item_owner(item_id) = loomx_get_owner_slug()
  );

COMMIT;
