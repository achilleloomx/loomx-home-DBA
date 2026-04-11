-- 20260411150000_loomx_item_agents_watcher_raci.sql
-- D-025 — Add 'watcher' role on loomx_item_agents (RACI "Informed") and extend
-- loomx_items RLS so co-engaged agents/people can see (and, for collaborators,
-- modify) items they are linked to.
--
-- Trigger: richiesta diretta Achille S018 — bisogno di marcare Vanessa come
-- "informata" sull'item GTD "Cercare un corso di Karate per Azzurra" (owner=achille)
-- senza darle permessi di modifica.
--
-- Semantica RACI mappata su loomx_item_agents.role:
--   - 'collaborator' = R/A — può leggere E modificare l'item (ma non eliminarlo)
--   - 'watcher'      = I   — può solo leggere l'item (Informed, read-only)
--
-- DELETE resta riservato all'owner / PMO. INSERT idem (un agente non si auto-aggiunge
-- come owner).
--
-- Cambiamenti strutturali:
--
-- 1. La FK `loomx_item_agents.agent_slug → board_agents(slug)` viene rimossa: con
--    l'introduzione del concetto di "watcher persona" (Vanessa) la colonna deve
--    poter referenziare anche slug di persone presenti in `loomx_owner_auth`,
--    non solo AI agents della rubrica `board_agents`. Stesso pattern di
--    `loomx_items.owner` che è TEXT libero senza FK.
--
-- 2. CHECK constraint sui valori ammessi di `role`. Nessun dato esistente quindi
--    safe (verificato: SELECT DISTINCT role → 0 righe).
--
-- 3. RLS su `loomx_item_agents` per il path authenticated (oggi esiste solo la
--    policy `doc_researcher_select_own_links`, scoped al session_user Postgres).
--    Le nuove policy permettono:
--      - SELECT: PMO, oppure se l'utente è il subject del link, oppure se è
--        l'owner dell'item linkato.
--      - INSERT/DELETE: PMO oppure owner dell'item linkato.
--    UPDATE non serve (i link sono PK + role, si cancella e si reinserisce).
--
-- 4. Estensione `loomx_items_select_authenticated` e `loomx_items_update_authenticated`
--    per includere il path co-engagement via `loomx_item_agents`. SELECT non
--    discrimina sul role (collaborator e watcher leggono entrambi), UPDATE invece
--    esige `role = 'collaborator'` per escludere i watcher.
--
-- Note out-of-scope (D-018 doc_researcher policies): le policy
-- `doc_researcher_select_engaged` / `doc_researcher_update_engaged` hanno già
-- la EXISTS su loomx_item_agents senza filtro role. Non vengono toccate qui per
-- non destabilizzare il POC RLS Phase 1 (D-019) appena validato; il researcher
-- in pratica non viene mai aggiunto come watcher. Follow-up tracciato in DECISIONS.

BEGIN;

-- ============================================================
-- 1. Allargare il dominio di agent_slug (drop FK su board_agents)
-- ============================================================

ALTER TABLE loomx_item_agents
  DROP CONSTRAINT IF EXISTS loomx_item_agents_agent_slug_fkey;

COMMENT ON COLUMN loomx_item_agents.agent_slug IS
  'Slug del subject ingaggiato sull''item: AI agent (board_agents.slug) o persona '
  '(loomx_owner_auth.owner_slug). FK rimossa volutamente — stesso pattern di '
  'loomx_items.owner.';

-- ============================================================
-- 2. CHECK constraint sul role (RACI)
-- ============================================================

ALTER TABLE loomx_item_agents
  ADD CONSTRAINT loomx_item_agents_role_check
  CHECK (role IN ('collaborator', 'watcher'));

COMMENT ON COLUMN loomx_item_agents.role IS
  'RACI mapping: collaborator = read+write (R/A), watcher = read-only (I = Informed). '
  'DELETE dell''item resta riservato a owner/PMO.';

-- ============================================================
-- 3. RLS authenticated path su loomx_item_agents
-- ============================================================

CREATE POLICY loomx_item_agents_select_authenticated
  ON loomx_item_agents FOR SELECT
  TO authenticated
  USING (
    loomx_is_pmo()
    OR agent_slug = loomx_get_owner_slug()
    OR EXISTS (
      SELECT 1 FROM loomx_items li
       WHERE li.id = loomx_item_agents.item_id
         AND li.owner = loomx_get_owner_slug()
    )
  );

CREATE POLICY loomx_item_agents_insert_authenticated
  ON loomx_item_agents FOR INSERT
  TO authenticated
  WITH CHECK (
    loomx_is_pmo()
    OR EXISTS (
      SELECT 1 FROM loomx_items li
       WHERE li.id = loomx_item_agents.item_id
         AND li.owner = loomx_get_owner_slug()
    )
  );

CREATE POLICY loomx_item_agents_delete_authenticated
  ON loomx_item_agents FOR DELETE
  TO authenticated
  USING (
    loomx_is_pmo()
    OR EXISTS (
      SELECT 1 FROM loomx_items li
       WHERE li.id = loomx_item_agents.item_id
         AND li.owner = loomx_get_owner_slug()
    )
  );

-- ============================================================
-- 4. Estensione policy authenticated su loomx_items
--    SELECT: + co-engaged (qualsiasi role)
--    UPDATE: + co-engaged role='collaborator' (watcher escluso)
--    DELETE: invariata (owner / PMO only)
--    INSERT: invariata (owner-self only)
-- ============================================================

DROP POLICY IF EXISTS loomx_items_select_authenticated ON loomx_items;
CREATE POLICY loomx_items_select_authenticated
  ON loomx_items FOR SELECT
  TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
    OR EXISTS (
      SELECT 1 FROM loomx_item_agents lia
       WHERE lia.item_id = loomx_items.id
         AND lia.agent_slug = loomx_get_owner_slug()
    )
  );

DROP POLICY IF EXISTS loomx_items_update_authenticated ON loomx_items;
CREATE POLICY loomx_items_update_authenticated
  ON loomx_items FOR UPDATE
  TO authenticated
  USING (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
    OR EXISTS (
      SELECT 1 FROM loomx_item_agents lia
       WHERE lia.item_id = loomx_items.id
         AND lia.agent_slug = loomx_get_owner_slug()
         AND lia.role = 'collaborator'
    )
  )
  WITH CHECK (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
    OR EXISTS (
      SELECT 1 FROM loomx_item_agents lia
       WHERE lia.item_id = loomx_items.id
         AND lia.agent_slug = loomx_get_owner_slug()
         AND lia.role = 'collaborator'
    )
  );

COMMIT;
