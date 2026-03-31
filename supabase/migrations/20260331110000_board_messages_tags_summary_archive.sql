-- Migration: board_messages evolution — tags, summary, archived_at
-- Date: 2026-03-31
-- Request: from 005/Postman via board message 7f4f7d2a
-- Description: Add tags, summary, and archive support to board_messages

-- 1. Tags — for topic filtering
ALTER TABLE board_messages ADD COLUMN tags TEXT[] NOT NULL DEFAULT '{}';

-- 2. Summary — short version for token-efficient reading
ALTER TABLE board_messages ADD COLUMN summary TEXT;

-- 3. Archived_at — soft-archive for old messages
ALTER TABLE board_messages ADD COLUMN archived_at TIMESTAMPTZ;

-- Index on tags for GIN-based filtering
CREATE INDEX idx_board_messages_tags ON board_messages USING GIN (tags);

-- Index on archived_at for filtering active messages
CREATE INDEX idx_board_messages_archived ON board_messages (archived_at) WHERE archived_at IS NULL;

-- Archive function: archive done/cancelled messages older than N days
CREATE OR REPLACE FUNCTION board_archive_old(p_days INTEGER DEFAULT 7)
RETURNS INTEGER AS $$
DECLARE
  archived_count INTEGER;
BEGIN
  UPDATE board_messages
  SET archived_at = now()
  WHERE status IN ('done', 'cancelled')
    AND archived_at IS NULL
    AND created_at < now() - (p_days || ' days')::INTERVAL;
  GET DIAGNOSTICS archived_count = ROW_COUNT;
  RETURN archived_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate board_overview view with new columns (DROP required: column list changed)
DROP VIEW IF EXISTS board_overview;
CREATE VIEW board_overview AS
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
  m.summary,
  m.body,
  m.status,
  m.tags,
  m.ref_id,
  m.archived_at
FROM board_messages m
JOIN board_agents f ON m.from_agent = f.agent_code
JOIN board_agents t ON m.to_agent = t.agent_code
WHERE m.archived_at IS NULL
ORDER BY m.created_at DESC;
