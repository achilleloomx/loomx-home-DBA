-- 20260407140000_doc_researcher_co_engagement.sql
-- Estende le policy RLS di doc_researcher su loomx_items per supportare
-- co-engagement via loomx_item_agents (D-018 / migration 20260407130000).
--
-- Strategia: drop+recreate (NON in-place ALTER POLICY, evita drift sulle USING/CHECK).
-- Le policy ora accettano:
--   - owner = 'researcher'                              (caso originale)
--   - waiting_on = 'researcher'                         (caso originale)
--   - co-engaged via loomx_item_agents.agent_slug='researcher' (NUOVO)
--
-- Inoltre `doc_researcher` ottiene SELECT su loomx_item_agents (filtrato dal proprio
-- slug) — gli serve per sapere "in quali item sono co-engaged".

BEGIN;

-- 1. SELECT su loomx_items: estesa con co-engagement
DROP POLICY IF EXISTS doc_researcher_select_engaged ON public.loomx_items;
CREATE POLICY doc_researcher_select_engaged ON public.loomx_items
  FOR SELECT TO doc_researcher
  USING (
    session_user = 'doc_researcher'
    AND (
      owner = 'researcher'
      OR waiting_on = 'researcher'
      OR EXISTS (
        SELECT 1 FROM public.loomx_item_agents lia
        WHERE lia.item_id = loomx_items.id
          AND lia.agent_slug = 'researcher'
      )
    )
  );

-- 2. UPDATE su loomx_items: estesa con co-engagement (USING + WITH CHECK simmetrici)
DROP POLICY IF EXISTS doc_researcher_update_engaged ON public.loomx_items;
CREATE POLICY doc_researcher_update_engaged ON public.loomx_items
  FOR UPDATE TO doc_researcher
  USING (
    session_user = 'doc_researcher'
    AND (
      owner = 'researcher'
      OR waiting_on = 'researcher'
      OR EXISTS (
        SELECT 1 FROM public.loomx_item_agents lia
        WHERE lia.item_id = loomx_items.id
          AND lia.agent_slug = 'researcher'
      )
    )
  )
  WITH CHECK (
    session_user = 'doc_researcher'
    AND (
      owner = 'researcher'
      OR waiting_on = 'researcher'
      OR EXISTS (
        SELECT 1 FROM public.loomx_item_agents lia
        WHERE lia.item_id = loomx_items.id
          AND lia.agent_slug = 'researcher'
      )
    )
  );

-- 3. INSERT policy (doc_researcher_insert_own) NON cambia: insert nuovi item
--    deve sempre avere owner='researcher'. Co-engagement è una membership additiva
--    creata DOPO via loomx_item_agents (tipicamente da Loomy o da un altro agente).

-- 4. SELECT su loomx_item_agents: doc_researcher vede solo i link che lo riguardano
GRANT SELECT ON public.loomx_item_agents TO doc_researcher;

DROP POLICY IF EXISTS doc_researcher_select_own_links ON public.loomx_item_agents;
CREATE POLICY doc_researcher_select_own_links ON public.loomx_item_agents
  FOR SELECT TO doc_researcher
  USING (
    session_user = 'doc_researcher'
    AND agent_slug = 'researcher'
  );

-- NB: doc_researcher NON ha INSERT/UPDATE/DELETE su loomx_item_agents.
-- La gestione dei link è prerogativa di Loomy (service_role) o di tool MCP
-- dedicati che verranno aggiunti da Postman in iterazione successiva.

COMMIT;
