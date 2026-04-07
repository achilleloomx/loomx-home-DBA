# RLS Phase 1 — POC Doc dockerizzato — Piano operativo DBA

> Riferimenti: D-019, D-020 (Loomy DECISIONS); `hub/initiatives/rls-security/design.md`;
> GTD `5919d745-9501-4320-a451-b6fa729f4db8` (next_action high).
> Aperto: 2026-04-06.

---

## 0. Conferma comprensione dei 6 hardening

| # | Hardening | Cosa significa per la migration |
|---|---|---|
| 4.1 | Solo Supavisor session mode (porta 5432) | Tutte le credenziali agente puntano a `aws-0-eu-west-3.pooler.supabase.com:5432` (mai 6543). Documentare nel runbook. |
| 4.2 | Ruoli `LOGIN NOINHERIT NOBYPASSRLS` + RLS su `session_user` | `CREATE ROLE doc_researcher LOGIN NOINHERIT NOBYPASSRLS PASSWORD '...'`. Zero `GRANT role TO role`. Tutte le policy `USING (session_user = 'doc_researcher')`. |
| 4.3 | Schema `agents` dedicato + REVOKE da public/anon/authenticated | `CREATE SCHEMA agents`; `REVOKE ALL ON SCHEMA public FROM doc_researcher`; tabelle dedicate vivono in `agents.*`. |
| 4.4 | Sandboxing per-agente (Docker) | Bitwarden CLI gira *dentro* il container. Mount namespace isolato → la session key non e' visibile ad altri processi host. |
| 4.5 | REVOKE su `pg_stat_*` + log shippati S3 append-only | `REVOKE SELECT ON pg_stat_statements, pg_stat_activity FROM doc_researcher`. pgaudit per ruolo, sink esterno (AWS S3 object lock). |
| 4.6 | Rotation script atomico | `ALTER ROLE ... VALID UNTIL 'now() - 1s'` → kick → set new password → restart container → verify `pg_stat_activity`. Da scrivere come script bash + dry-run in staging prima della prod. |

Comprensione confermata. La migration parte SOLO dopo i 3 gap empirici.

---

## 1. Setup ambiente staging

**Decisione D-019:** schema separato sullo stesso progetto Supabase (`fvoxccwfysazwpchudwp`).

- Schema staging: `agents_staging` (parallelo a quello che diventera' `agents` in prod)
- Tabelle reali in lettura: usiamo le viste/tabelle prod come read-only per i test, **mai** scritture cross-namespace dal POC
- Password ruoli generate con `openssl rand -base64 32`, storate in Bitwarden vault `LoomX/agents`
- Connessione: `psql "postgresql://doc_researcher:<pwd>@aws-0-eu-west-3.pooler.supabase.com:5432/postgres?sslmode=require&options=--cluster%3Dfvoxccwfysazwpchudwp"`

**Blocker:** nessun `supabase` CLI installato sull'host DBA. Le migration vanno applicate da Achille via Supabase Studio o CLI sul suo PC. Da risolvere prima di poter eseguire i gap test.

---

## 2. I 3 gap empirici (gate prima della migration agents)

### Gap A — Supavisor session mode con 10 ruoli concorrenti

**Domanda:** una connessione del pool Supavisor session mode puo' essere riusata con identita' di un altro agente?

**Setup:**
1. Creare 10 ruoli di test in `agents_staging`: `t01..t10`, ciascuno LOGIN NOINHERIT NOBYPASSRLS, password unica.
2. Tabella canary `agents_staging.canary (owner text, payload text)`, RLS `USING (session_user = owner)`.
3. Seed: 1 riga per ruolo, `owner='t0X'`.
4. Script Python che apre 10 worker concorrenti, ognuno con la propria credenziale, per 5 minuti, eseguendo `SELECT current_user, session_user, * FROM agents_staging.canary` 10×/sec.

**Pass criteria:** ogni worker vede ESCLUSIVAMENTE la propria riga. Zero cross-leak in 30k+ query totali. `session_user` mai diverso da quello della credenziale di login.

**Fail mitigation:** se leak osservato, escalation a Loomy + Achille. Possibile workaround: connessioni dirette al primary (no pooler) → costo: scalabilita' connessioni.

### Gap B — REVOKE su `pg_stat_activity` vs Supabase Dashboard

**Domanda:** revocare SELECT su `pg_stat_activity` ai ruoli agente rompe la dashboard managed?

**Setup:**
1. `REVOKE SELECT ON pg_catalog.pg_stat_activity FROM doc_researcher`.
2. Aprire dashboard Supabase Studio in browser (sezioni: Database → Roles, Database → Reports, Auth → Users).
3. Verificare che il ruolo `service_role` (usato dalla dashboard) sia INTATTO — la REVOKE riguarda solo i ruoli agente.

**Pass criteria:** dashboard funzionante. Il ruolo `doc_researcher` riceve `permission denied` su `pg_stat_activity` da `psql`.

**Fail mitigation:** in teoria zero rischio (la dashboard usa service_role, non `doc_researcher`). Se rotto, rollback con `GRANT SELECT (... colonne minime ...) ON pg_stat_activity TO doc_researcher`.

### Gap C — Setup Docker base per agente Claude Code

**Domanda:** Dockerfile minimo, mount, env injection da Bitwarden CLI funzionano end-to-end?

**Setup:**
1. `Dockerfile.doc-researcher` base:
   - `FROM node:20-bookworm-slim`
   - install: `claude-code` CLI, `bw` CLI, `psql`, `python3`
   - non-root user `agent` (uid 1000)
   - workdir `/work`
2. Bind mount: `${HUB}/researcher` → `/work`
3. Entrypoint script `entrypoint.sh`:
   - `bw login --apikey` (env: `BW_CLIENTID`, `BW_CLIENTSECRET`)
   - `export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)`
   - `bw get password loomx/agents/doc_researcher > $RUNTIME_DIR/db_password`
   - genera `.mcp.json` da template con la credenziale
   - `exec claude code`
4. Test: container avviato, `psql -c "SELECT current_user, session_user;"` → ritorna `doc_researcher` su entrambi.

**Pass criteria:** container parte, `bw unlock` riesce, credential mai scritta su disco persistente, `psql` autentica con il ruolo nativo.

**Blocker:** richiede credenziali Bitwarden vault iniziali da Achille (msg `0867882a` — canale sicuro fuori board).

---

## 3. Migration `agents` schema + ruolo `doc_researcher` (post-gap)

Si scrive SOLO se i 3 gap passano. Bozza nel commento sotto, non committata come migration finche' non gate-passed.

```sql
-- DRAFT — non eseguire prima del gate gap A/B/C
BEGIN;
CREATE SCHEMA IF NOT EXISTS agents;
REVOKE ALL ON SCHEMA agents FROM PUBLIC, anon, authenticated;

-- Ruolo nativo
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doc_researcher') THEN
    CREATE ROLE doc_researcher LOGIN NOINHERIT NOBYPASSRLS PASSWORD '__SET_VIA_BW__';
  END IF;
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM doc_researcher;
REVOKE SELECT ON pg_catalog.pg_stat_statements FROM doc_researcher;
REVOKE SELECT ON pg_catalog.pg_stat_activity FROM doc_researcher;

-- GRANT chirurgici (D-018: tutti possono INSERT GTD; UPDATE solo su righe ingaggiate)
GRANT INSERT ON board_messages TO doc_researcher;
GRANT INSERT ON loomx_items TO doc_researcher;
GRANT SELECT, UPDATE ON loomx_items TO doc_researcher;  -- filtrato da policy

-- RLS policy basata su session_user (NON current_user)
CREATE POLICY doc_researcher_own_items ON loomx_items
  FOR UPDATE TO doc_researcher
  USING (
    owner = 'researcher'
    OR waiting_on = 'researcher'
    -- TODO: co-engagement via loomx_item_agents quando D-018 verra' implementato
  );

-- pgaudit per ruolo (richiede extension gia' attiva)
ALTER ROLE doc_researcher SET pgaudit.log = 'write,ddl';

COMMIT;
```

---

## 4. Dockerfile completo + agent_manager.py Docker-aware

Dipende da Gap C. Skeleton documentato in §2 Gap C. agent_manager.py:
- nuovo flag `--docker` per agente
- `invoke()` → `docker exec -i <container> claude code -p <prompt>`
- `interactive()` → `docker exec -it <container> claude code`
- `status()` → `docker inspect --format '{{.State.Status}}' <container>`
- retrocompatibilita': se l'agente non e' in `docker_agents.json`, comportamento attuale (subprocess host).

---

## 5. Stato attuale — riepilogo blocker

| Step | Stato | Blocker |
|---|---|---|
| Pre-flight: lettura D-019/D-020 + design.md | ✅ done | — |
| Migration initiative `rls-security` | ✅ scritta | Da applicare (no CLI sul DBA) |
| Setup staging schema | ⏸ blocked | No `supabase` CLI sull'host DBA. Achille deve applicare migration o installare CLI. |
| Gap A test (Supavisor leak) | ⏸ blocked | Dipende da setup staging. |
| Gap B test (REVOKE pg_stat_activity) | ⏸ blocked | Dipende da setup staging. |
| Gap C test (Docker base) | ⏸ blocked | Dipende da credenziali Bitwarden vault iniziali da Achille. |
| Migration `agents` + `doc_researcher` | bozza in §3 | Gate dei 3 gap. |
| Dockerfile completo Doc | bozza in §2 Gap C | Gap C. |
| `agent_manager.py` Docker-aware | skeleton in §4 | Gap C. |

**Richiesta a Loomy/Achille:** sbloccare almeno uno tra (a) installazione `supabase` CLI sull'host DBA + service_role per applicare migration in staging, oppure (b) Achille applica le migration manualmente via Studio quando le invio. Senza questo non si parte con i gap.
