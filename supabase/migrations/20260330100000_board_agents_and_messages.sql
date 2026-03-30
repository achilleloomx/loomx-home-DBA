-- Migration: board_agents + board_messages
-- Date: 2026-03-30
-- Namespace: board_*
-- Requirements: REQ-001 through REQ-012
-- Description: Agent registry and inter-agent messaging system

-- ============================================================
-- 1. board_agents — agent registry ("phone book")
-- REQ-001, REQ-002, REQ-003, REQ-004
-- ============================================================

CREATE TABLE board_agents (
  agent_code  TEXT PRIMARY KEY,                          -- '001', '002', ...
  slug        TEXT NOT NULL UNIQUE,                      -- 'pm-home', 'dba'
  label       TEXT NOT NULL,                             -- 'Project Manager — LoomX Home'
  nickname    TEXT,                                      -- friendly name, defaults to label via trigger
  scope       TEXT NOT NULL,                             -- responsibilities description
  repo        TEXT,                                      -- repository name
  active      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- REQ-003: nickname defaults to label
CREATE OR REPLACE FUNCTION board_agents_default_nickname()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.nickname IS NULL THEN
    NEW.nickname := NEW.label;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_board_agents_default_nickname
  BEFORE INSERT OR UPDATE ON board_agents
  FOR EACH ROW
  EXECUTE FUNCTION board_agents_default_nickname();

-- REQ-012: RLS enabled, deny-all
ALTER TABLE board_agents ENABLE ROW LEVEL SECURITY;

-- REQ-004: seed initial agents
INSERT INTO board_agents (agent_code, slug, label, nickname, scope, repo) VALUES
  ('001', 'pm-home',    'Project Manager — LoomX Home',        NULL,       'Coordinamento progetto LoomX Home',            'loomx-home-pm'),
  ('002', 'dba',        'Database Administrator — LoomX Home',  NULL,       'Schema Supabase, migrazioni, RLS, permessi',   'loomx-home-DBA'),
  ('003', 'app',        'Product Owner — LoomX Home',           NULL,       'Sviluppo PWA famiglia',                        'loomx-home-app'),
  ('004', 'assistant',  'Home Assistant — LoomX Home',          'Evaristo', 'Assistente domestico famiglia',                'loomx-home-assistant');

-- ============================================================
-- 2. board_messages — inter-agent messaging
-- REQ-005 through REQ-011
-- ============================================================

CREATE TABLE board_messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_agent  TEXT NOT NULL REFERENCES board_agents(agent_code),
  to_agent    TEXT NOT NULL REFERENCES board_agents(agent_code),
  type        TEXT NOT NULL,
  subject     TEXT NOT NULL,
  body        TEXT NOT NULL,
  ref_id      UUID REFERENCES board_messages(id),          -- REQ-009: self-ref for message chains
  status      TEXT NOT NULL DEFAULT 'pending',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- REQ-006: sender != receiver
  CONSTRAINT chk_board_messages_no_self CHECK (from_agent <> to_agent),

  -- REQ-007: allowed message types
  CONSTRAINT chk_board_messages_type CHECK (type IN ('task', 'question', 'blocker', 'done', 'alignment_issue')),

  -- REQ-008: allowed statuses
  CONSTRAINT chk_board_messages_status CHECK (status IN ('pending', 'acknowledged', 'in_progress', 'done', 'cancelled'))
);

-- REQ-010: indexes for main query patterns
CREATE INDEX idx_board_messages_to_agent_status ON board_messages (to_agent, status);
CREATE INDEX idx_board_messages_from_agent ON board_messages (from_agent);
CREATE INDEX idx_board_messages_ref_id ON board_messages (ref_id);

-- REQ-011: auto-update updated_at
CREATE OR REPLACE FUNCTION board_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_board_messages_updated_at
  BEFORE UPDATE ON board_messages
  FOR EACH ROW
  EXECUTE FUNCTION board_update_timestamp();

-- REQ-012: RLS enabled, deny-all
ALTER TABLE board_messages ENABLE ROW LEVEL SECURITY;
