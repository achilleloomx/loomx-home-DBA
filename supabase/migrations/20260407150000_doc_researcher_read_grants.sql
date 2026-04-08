-- 20260407150000_doc_researcher_read_grants.sql
-- RLS Phase 1 — bug-fix from S014 7-step test (D-023 §4)
--
-- The original 20260407100000 migration granted INSERT on board_messages and
-- the loomx_items grants needed for GTD, but missed two read paths required
-- by the Board MCP server when it runs as `doc_researcher`:
--
--   1. SELECT on board_agents — needed at MCP startup by resolveAgentRegistry()
--      to build the slug↔code map. Without it the server cannot start.
--   2. SELECT on board_messages — needed by board_inbox so the agent can read
--      messages addressed to it (filtered by RLS policy).
--
-- Both fixes were applied live during S014 testing for board_agents (POLICY
-- only); this migration formalizes them and adds the board_messages path.
--
-- Companion to D-023 (DBA repo) and the 7-step spec.

BEGIN;

-- 1. board_agents — public registry, every per-agent role needs to read it.
GRANT SELECT ON public.board_agents TO doc_researcher;

DROP POLICY IF EXISTS board_agents_select_doc_researcher ON public.board_agents;
CREATE POLICY board_agents_select_doc_researcher ON public.board_agents
  FOR SELECT TO doc_researcher
  USING (true);

-- 2. board_messages — researcher can read only messages it sent or received.
--    Codes from board_agents: researcher = '021'.
GRANT SELECT ON public.board_messages TO doc_researcher;

DROP POLICY IF EXISTS doc_researcher_select_messages ON public.board_messages;
CREATE POLICY doc_researcher_select_messages ON public.board_messages
  FOR SELECT TO doc_researcher
  USING (
    session_user = 'doc_researcher'
    AND (to_agent = '021' OR from_agent = '021')
  );

COMMIT;
