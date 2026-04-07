-- 20260407100000_agents_schema_doc_researcher.sql
-- RLS Phase 1 — D-019, D-021, RLS_PHASE1_PLAN.md
-- Creates the `agents` schema and the first native Postgres role `doc_researcher`
-- used by the dockerized Doc agent (Gap C POC).
--
-- Hardening references (RLS_PHASE1_PLAN.md §0):
--   4.1 Supavisor session mode (porta 5432) — enforced via connection string, not SQL
--   4.2 LOGIN NOINHERIT NOBYPASSRLS + RLS on session_user
--   4.3 Dedicated `agents` schema, REVOKE from public/anon/authenticated
--   4.4 Sandboxing — Docker (out of SQL scope)
--   4.5 REVOKE pg_stat_statements (NOTE: pg_stat_activity declassed per D-021,
--       no-op silente sul managed; lasciato come commento per tracciabilità)
--   4.6 Rotation script — out of SQL scope, separate runbook
--
-- IMPORTANT: the password placeholder must be replaced at apply-time with the
-- value stored in Bitwarden vault `loomx/agents/doc_researcher`. DO NOT commit
-- a real password. Apply via Supabase Studio (no supabase CLI on DBA host).

BEGIN;

-- 1. Schema dedicated to agent-owned objects (currently empty; reserved for future use).
CREATE SCHEMA IF NOT EXISTS agents;
REVOKE ALL ON SCHEMA agents FROM PUBLIC;
REVOKE ALL ON SCHEMA agents FROM anon;
REVOKE ALL ON SCHEMA agents FROM authenticated;

-- 2. Native Postgres role for the Doc agent.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doc_researcher') THEN
    -- Password set via Studio at apply-time; replaced post-rotation by ops runbook.
    EXECUTE 'CREATE ROLE doc_researcher LOGIN NOINHERIT NOBYPASSRLS PASSWORD ''__REPLACE_AT_APPLY_TIME__''';
  END IF;
END $$;

-- 3. Defensive REVOKEs — strip everything inherited from public defaults.
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM doc_researcher;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM doc_researcher;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM doc_researcher;
REVOKE ALL ON SCHEMA public FROM doc_researcher;
GRANT  USAGE ON SCHEMA public TO doc_researcher;

-- 4.5 (parziale, D-021): pg_stat_statements REVOKE resta obbligatorio.
--     pg_stat_activity REVOKE descoped: grantor è supabase_admin, non revocabile dal nostro postgres.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
    EXECUTE 'REVOKE SELECT ON pg_stat_statements FROM doc_researcher';
  END IF;
END $$;

-- 4. Surgical GRANTs (D-018): Doc may post messages and create/update only its own GTD items.
GRANT INSERT                  ON public.board_messages TO doc_researcher;
GRANT SELECT, INSERT, UPDATE  ON public.loomx_items    TO doc_researcher;

-- 5. RLS policies — keyed on session_user (not current_user) per hardening 4.2.
ALTER TABLE public.loomx_items    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.board_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS doc_researcher_select_engaged ON public.loomx_items;
CREATE POLICY doc_researcher_select_engaged ON public.loomx_items
  FOR SELECT TO doc_researcher
  USING (
    session_user = 'doc_researcher'
    AND (owner = 'researcher' OR waiting_on = 'researcher')
    -- TODO co-engagement via loomx_item_agents quando D-018 sarà implementato
  );

DROP POLICY IF EXISTS doc_researcher_insert_own ON public.loomx_items;
CREATE POLICY doc_researcher_insert_own ON public.loomx_items
  FOR INSERT TO doc_researcher
  WITH CHECK (
    session_user = 'doc_researcher'
    AND owner = 'researcher'
  );

DROP POLICY IF EXISTS doc_researcher_update_engaged ON public.loomx_items;
CREATE POLICY doc_researcher_update_engaged ON public.loomx_items
  FOR UPDATE TO doc_researcher
  USING (
    session_user = 'doc_researcher'
    AND (owner = 'researcher' OR waiting_on = 'researcher')
  )
  WITH CHECK (
    session_user = 'doc_researcher'
    AND (owner = 'researcher' OR waiting_on = 'researcher')
  );

DROP POLICY IF EXISTS doc_researcher_insert_messages ON public.board_messages;
CREATE POLICY doc_researcher_insert_messages ON public.board_messages
  FOR INSERT TO doc_researcher
  WITH CHECK (
    session_user = 'doc_researcher'
    -- board_messages.from_agent stores the numeric agent_code (see board_agents);
    -- 'researcher' has code '021'.
    AND from_agent = '021'
  );

-- 6. pgaudit per ruolo (extension required separately; harmless if absent).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgaudit') THEN
    EXECUTE 'ALTER ROLE doc_researcher SET pgaudit.log = ''write,ddl''';
  END IF;
END $$;

COMMIT;
