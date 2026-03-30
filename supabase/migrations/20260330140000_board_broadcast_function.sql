-- Migration: board_broadcast function
-- Date: 2026-03-30
-- Description: Convenience function to send a message to all active agents

CREATE OR REPLACE FUNCTION board_broadcast(
  p_from_agent TEXT,
  p_type TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_ref_id UUID DEFAULT NULL
)
RETURNS SETOF board_messages AS $$
BEGIN
  RETURN QUERY
  INSERT INTO board_messages (from_agent, to_agent, type, subject, body, ref_id)
  SELECT
    p_from_agent,
    a.agent_code,
    p_type,
    p_subject,
    p_body,
    p_ref_id
  FROM board_agents a
  WHERE a.active = true
    AND a.agent_code <> p_from_agent
  RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
