-- Migration: Register Loomy + consulting agents + loomx_* namespace
-- Date: 2026-04-05
-- Namespace: board_* (agent updates), loomx_* (new namespace)
-- Decisions: D-001 (Loomy root), D-003 (Supabase esteso), D-004 (GTD nel DB)
-- Source: hub/migrations/001_register_loomy_and_namespace.sql
-- Note: RLS policies corrected to deny-all pattern (service_role bypasses RLS)

-- ============================================================
-- 1. Update board_agents: pm-home -> loomy (D-001)
-- ============================================================

UPDATE board_agents
SET slug     = 'loomy',
    label    = 'Loomy — LoomX Root Coordinator',
    nickname = 'Loomy',
    scope    = 'Coordina tutti i progetti LoomX (consulting + Home). Evoluzione del PM Home.',
    repo     = '00. LoomX Consulting'
WHERE slug = 'pm-home';

-- Register new consulting agents
INSERT INTO board_agents (agent_code, slug, label, nickname, scope, repo, active)
VALUES
  ('010', 'sito-loomx',           'Product Owner — Sito LoomX',           'Sito LoomX',     'Sito web LoomX Consulting (Next.js)',          'LoomXweb',                    true),
  ('011', 'loomx-commercialisti', 'Product Owner — LoomX Commercialisti', 'Commercialisti',  'App marginalita studi commercialisti',          'LoomXCommercialisti',         true),
  ('012', 'damato',               'Product Owner — D''Amato Arredamenti', 'D''Amato',        'Sito web D''Amato Arredamenti',                'DamatoArredamenti_Website',   true),
  ('013', 'sintesi-impianti',     'Consulting — Sintesi Impianti',        'Sintesi',         'Progetto consulting Sintesi Impianti',          NULL,                          true)
ON CONFLICT (slug) DO NOTHING;

-- ============================================================
-- 2. Create loomx_* namespace tables (D-003)
-- ============================================================

-- Clients
CREATE TABLE IF NOT EXISTS loomx_clients (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  short_name    TEXT UNIQUE,
  sector        TEXT,
  size          TEXT,                -- e.g. '1-10M', '10-50M'
  contact_email TEXT,
  contact_name  TEXT,
  notes         TEXT,
  status        TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'prospect')),
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now()
);

-- Projects
CREATE TABLE IF NOT EXISTS loomx_projects (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  short_name  TEXT UNIQUE,
  client_id   UUID REFERENCES loomx_clients(id),
  type        TEXT CHECK (type IN ('consulting', 'tech', 'personal', 'presales', 'internal')),
  agent_id    TEXT,                  -- slug of the responsible agent
  repo        TEXT,                  -- GitHub repo name if applicable
  local_path  TEXT,                  -- local filesystem path
  status      TEXT DEFAULT 'active' CHECK (status IN ('active', 'paused', 'done', 'archived')),
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- Tags
CREATE TABLE IF NOT EXISTS loomx_tags (
  id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name  TEXT UNIQUE NOT NULL,
  color TEXT
);

-- GTD Items (D-004)
CREATE TABLE IF NOT EXISTS loomx_items (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title        TEXT NOT NULL,
  body         TEXT,
  gtd_status   TEXT DEFAULT 'inbox' CHECK (gtd_status IN (
    'inbox', 'next_action', 'waiting_for', 'project_task',
    'calendar', 'someday', 'done', 'trash'
  )),
  owner        TEXT,                 -- agent_id or 'achille'
  waiting_on   TEXT,                 -- who we're waiting for (if waiting_for)
  priority     TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  deadline     TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  source       TEXT,                 -- where this item came from (meeting, email, board, manual)
  source_ref   TEXT,                 -- reference to source (message_id, meeting name, etc.)
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

-- Item-Project mapping (N:N)
CREATE TABLE IF NOT EXISTS loomx_item_projects (
  item_id    UUID REFERENCES loomx_items(id) ON DELETE CASCADE,
  project_id UUID REFERENCES loomx_projects(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, project_id)
);

-- Item-Tag mapping (N:N)
CREATE TABLE IF NOT EXISTS loomx_item_tags (
  item_id UUID REFERENCES loomx_items(id) ON DELETE CASCADE,
  tag_id  UUID REFERENCES loomx_tags(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, tag_id)
);

-- Document index
CREATE TABLE IF NOT EXISTS loomx_documents (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  path          TEXT UNIQUE NOT NULL,
  filename      TEXT NOT NULL,
  doc_type      TEXT,                -- md, pdf, xlsx, pptx, py, ts, etc.
  title         TEXT,
  description   TEXT,
  project_id    UUID REFERENCES loomx_projects(id),
  agent_id      TEXT,                -- slug of owner agent
  status        TEXT DEFAULT 'active' CHECK (status IN ('active', 'archived', 'deleted')),
  size_bytes    BIGINT,
  last_modified TIMESTAMPTZ,
  indexed_at    TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 3. Views for Loomy
-- ============================================================

CREATE OR REPLACE VIEW loomx_v_inbox AS
SELECT i.*, array_agg(ip.project_id) AS project_ids
FROM loomx_items i
LEFT JOIN loomx_item_projects ip ON i.id = ip.item_id
WHERE i.gtd_status = 'inbox'
GROUP BY i.id
ORDER BY i.priority DESC, i.created_at;

CREATE OR REPLACE VIEW loomx_v_next_actions AS
SELECT i.*, array_agg(ip.project_id) AS project_ids
FROM loomx_items i
LEFT JOIN loomx_item_projects ip ON i.id = ip.item_id
WHERE i.gtd_status = 'next_action'
GROUP BY i.id
ORDER BY i.priority DESC, i.deadline NULLS LAST;

CREATE OR REPLACE VIEW loomx_v_waiting_for AS
SELECT i.*, array_agg(ip.project_id) AS project_ids
FROM loomx_items i
LEFT JOIN loomx_item_projects ip ON i.id = ip.item_id
WHERE i.gtd_status = 'waiting_for'
GROUP BY i.id
ORDER BY i.deadline NULLS LAST;

CREATE OR REPLACE VIEW loomx_v_project_dashboard AS
SELECT
  p.id          AS project_id,
  p.name        AS project_name,
  p.status      AS project_status,
  i.gtd_status,
  COUNT(i.id)   AS item_count
FROM loomx_projects p
LEFT JOIN loomx_item_projects ip ON p.id = ip.project_id
LEFT JOIN loomx_items i ON ip.item_id = i.id
GROUP BY p.id, p.name, p.status, i.gtd_status
ORDER BY p.name, i.gtd_status;

-- ============================================================
-- 4. RLS — deny-all pattern (service_role bypasses RLS)
-- ============================================================
-- Note: NO explicit policies created. In Supabase, service_role
-- bypasses RLS automatically. With RLS enabled and no policies,
-- anon and authenticated roles have zero access.
-- This matches the existing board_* pattern.

ALTER TABLE loomx_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE loomx_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE loomx_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE loomx_item_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE loomx_item_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE loomx_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE loomx_documents ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 5. Seed data
-- ============================================================

-- Seed clients
INSERT INTO loomx_clients (name, short_name, sector, status) VALUES
  ('LoomX Consulting',    'loomx',   'consulting',       'active'),
  ('D''Amato Arredamenti','damato',  'retail/furniture',  'active'),
  ('Sintesi Impianti',    'sintesi', 'industrial',        'active'),
  ('Famiglia Barban',     'home',    'personal',          'active')
ON CONFLICT (short_name) DO NOTHING;

-- Seed tags
INSERT INTO loomx_tags (name) VALUES
  ('urgent'), ('governance'), ('marketing'), ('tech'), ('consulting'),
  ('home'), ('blocked'), ('review'), ('migration')
ON CONFLICT (name) DO NOTHING;
