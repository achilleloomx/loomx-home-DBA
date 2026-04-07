-- Initiative pilot: rls-security
-- Tracks the cross-project effort to migrate agent access on Supabase
-- from shared service_role to per-agent native Postgres roles (D-019/D-020).
--
-- Uses existing loomx_projects + loomx_item_projects tables (created in
-- 20260405100000_loomx_namespace_and_agent_updates.sql).
--
-- NOTE on schema vs. request: Loomy asked for owner_agent/sponsor_agent
-- columns. The existing table only has a single agent_id (responsible).
-- We map owner_agent -> agent_id ('dba'), and record sponsor ('loomy')
-- inside notes. If the dual ownership becomes load-bearing for the
-- initiatives pattern, a follow-up migration can add sponsor_agent.

BEGIN;

-- 1. Insert the initiative row (idempotent on short_name UNIQUE)
INSERT INTO loomx_projects (short_name, name, type, agent_id, status, notes)
VALUES (
  'rls-security',
  'RLS Security (isolamento agenti Supabase)',
  'internal',
  'dba',
  'active',
  'Initiative pilota per il pattern hub/initiatives. Sponsor: loomy. Owner tecnico: dba. Vedi hub/initiatives/rls-security/design.md e D-019/D-020.'
)
ON CONFLICT (short_name) DO UPDATE
  SET name      = EXCLUDED.name,
      type      = EXCLUDED.type,
      agent_id  = EXCLUDED.agent_id,
      status    = EXCLUDED.status,
      notes     = EXCLUDED.notes,
      updated_at = now();

-- 2. Link the 6 GTD items to the initiative
WITH p AS (
  SELECT id FROM loomx_projects WHERE short_name = 'rls-security'
)
INSERT INTO loomx_item_projects (item_id, project_id)
SELECT item_id, p.id
FROM p, (VALUES
  ('e402d9d1-e186-4d72-8f09-557bff84cb5e'::uuid),  -- DBA utenti Supabase + RLS (originale)
  ('5919d745-9501-4320-a451-b6fa729f4db8'::uuid),  -- POC end-to-end Doc dockerizzato (Fase 1)
  ('0eafa755-cffc-4b2d-882f-30a4be3c517a'::uuid),  -- Achille crea Bitwarden (bloccante)
  ('0b23caca-47fa-4890-ba3c-2644a54b545a'::uuid),  -- Fase 2 rollout 9 agenti
  ('2f33caf0-1ad2-445b-9171-87d95b538043'::uuid),  -- Fase 3 multi-PC ghcr.io
  ('2619589f-bd2d-47ec-9bce-2cf479408e69'::uuid)   -- Fase 4 VPS Hetzner + rclone
) AS items(item_id)
ON CONFLICT (item_id, project_id) DO NOTHING;

COMMIT;
