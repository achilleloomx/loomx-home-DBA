-- 20260407130000_loomx_item_agents.sql
-- D-018 (locale: D-018) — co-engagement N:N item↔agent.
--
-- Trigger: msg b45ea879 (Loomy → DBA, 2026-04-07).
-- Sblocca la generalizzazione delle policy RLS per-agente: oggi `doc_researcher`
-- può vedere/modificare solo righe dove `owner='researcher'` o `waiting_on='researcher'`;
-- con questa tabella un item può avere più agenti "ingaggiati" senza forzarli
-- nei due campi singoli.
--
-- DIVERGENZA da proposta Loomy: la FK su `agent_slug` punta a `board_agents(slug)`
-- (UNIQUE), NON a `loomx_agents(slug)` — quella tabella non esiste nello schema
-- corrente. La rubrica unica degli agenti è `board_agents` (D-001).
--
-- Naming `role` libero (TEXT) come da indicazione Loomy, niente CHECK constraint:
-- valori suggeriti 'collaborator' | 'reviewer' | 'observer', formalizzati se serve.

BEGIN;

CREATE TABLE loomx_item_agents (
  item_id    UUID NOT NULL REFERENCES loomx_items(id)        ON DELETE CASCADE,
  agent_slug TEXT NOT NULL REFERENCES board_agents(slug)     ON DELETE CASCADE,
  role       TEXT NOT NULL DEFAULT 'collaborator',
  added_by   TEXT NOT NULL,  -- slug agente che ha creato il link (audit)
  added_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (item_id, agent_slug)
);

-- Index per la query "tutti gli item co-engaged da uno specifico agente"
CREATE INDEX loomx_item_agents_agent_slug_idx
  ON loomx_item_agents (agent_slug);

-- RLS deny-all (stesso pattern di loomx_items): service_role bypassa,
-- i ruoli per-agente accederanno via policy esplicite scritte nelle loro migration.
ALTER TABLE loomx_item_agents ENABLE ROW LEVEL SECURITY;

COMMIT;
