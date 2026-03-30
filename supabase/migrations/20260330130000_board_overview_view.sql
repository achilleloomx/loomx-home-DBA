-- Migration: board_overview view for PM admin monitoring
-- Date: 2026-03-30
-- Request: from 001/PM via board message b9b194c4

-- View that joins board_messages with board_agents for human-readable output
-- Used by the Board MCP tool (board_admin / board_overview)
-- Access: service role only (view inherits RLS from underlying tables)

CREATE OR REPLACE VIEW board_overview AS
SELECT
  m.id,
  m.created_at,
  m.updated_at,
  f.agent_code  AS from_code,
  f.slug        AS from_slug,
  f.nickname    AS from_name,
  t.agent_code  AS to_code,
  t.slug        AS to_slug,
  t.nickname    AS to_name,
  m.type,
  m.subject,
  m.body,
  m.status,
  m.ref_id
FROM board_messages m
JOIN board_agents f ON m.from_agent = f.agent_code
JOIN board_agents t ON m.to_agent = t.agent_code
ORDER BY m.created_at DESC;
