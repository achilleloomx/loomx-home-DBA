# DECISIONS — LoomX Home DBA

> Decisioni architetturali relative al database. Status vuoto = attiva. `superseded` = sostituita.

---

### D-001 — Agent registry con codice numerico progressivo
**Tags:** schema, board
**Data:** 2026-03-30

Gli agenti sono identificati da un codice numerico progressivo a 3 cifre (TEXT PK) nella tabella `board_agents`, invece di CHECK constraint hardcoded su `from_agent`/`to_agent`. Motivazione: scalabilità — nuovo agente = INSERT, non migrazione.

### D-002 — Nickname defaults to label via trigger
**Tags:** schema, board
**Data:** 2026-03-30

Se `nickname` è NULL, un trigger BEFORE INSERT/UPDATE lo popola con il valore di `label`. Evita duplicazione logica a livello applicativo.

### D-003 — RLS deny-all per tabelle board_*
**Tags:** security, board
**Data:** 2026-03-30

Le tabelle `board_*` hanno RLS abilitato senza policy esplicite (deny-all). Il Board MCP usa service role key che bypassa RLS nativamente. Nessun accesso da `anon` o `authenticated`.

### D-004 — Progetto Supabase unico per LoomX Home
**Tags:** infra
**Data:** 2026-03-30

Tutti i namespace (`board_*`, `home_*`, futuri) condividono un unico progetto Supabase: `fvoxccwfysazwpchudwp` (EU West Paris). Il DBA è owner dello schema, gli altri agenti contribuiscono via PR/request.

### D-005 — Prefisso fisico `home_` su tutte le tabelle app
**Tags:** schema, naming, home
**Data:** 2026-03-30

Tutte le tabelle dell'app famiglia hanno prefisso fisico `home_` (es. `home_families`, `home_profiles`, `home_shopping_lists`). Le funzioni helper seguono la stessa convenzione (`home_get_my_family_id()`, `home_seed_default_categories()`). L'app (loomx-home-app) deve aggiornare le sue query per usare i nomi prefissati. Migrazione: `20260330110000_home_schema.sql`.

### D-006 — board_messages: tags, summary, archived_at
**Tags:** schema, board
**Data:** 2026-03-31

Evoluzione dello schema board_messages su richiesta di 005/Postman (product owner piattaforma comunicazione, D-008 PM). Colonne additive: `tags TEXT[]` per filtering per topic, `summary TEXT` per lettura token-efficient, `archived_at TIMESTAMPTZ` per soft-archive. Function `board_archive_old(days)` archivia messaggi done/cancelled. View `board_overview` aggiornata per escludere archiviati e includere nuovi campi.

### D-007 — Namespace loomx_* per root agent Loomy
**Tags:** schema, loomx, security
**Data:** 2026-04-05

Estensione del Supabase LoomX Home con namespace `loomx_*` per anagrafica clienti, progetti, GTD items, tags e documenti. Decisione cross-progetto D-003 (hub). Tabelle: `loomx_clients`, `loomx_projects`, `loomx_items`, `loomx_item_projects`, `loomx_item_tags`, `loomx_tags`, `loomx_documents`. Views: `loomx_v_inbox`, `loomx_v_next_actions`, `loomx_v_waiting_for`, `loomx_v_project_dashboard`. RLS: deny-all (stesso pattern D-003 DBA). Agenti consulting registrati: 010-013.

### D-008 — Correzione RLS: deny-all per loomx_* (divergenza dal sorgente)
**Tags:** security, loomx
**Data:** 2026-04-05

Il file sorgente (`hub/migrations/001_register_loomy_and_namespace.sql`) creava policy `service_role_full_access` con `USING (true) WITH CHECK (true)` — questo avrebbe dato accesso completo a `anon` e `authenticated`, non solo a service_role. Corretto nella migrazione DBA applicando il pattern deny-all consolidato (D-003): RLS enabled, nessuna policy esplicita, service_role bypassa automaticamente.

### D-010 — Initiative pattern: `loomx_projects` riusato per temi cross-progetto
**Tags:** governance, schema, loomx
**Data:** 2026-04-06

Loomy ha introdotto il pattern "initiatives" (temi cross-progetto con cartella `hub/initiatives/<slug>/`, doc propria, durata pluri-settimanale, non clienti). Per il tracking DB **riusiamo `loomx_projects`** (gia' creata in `20260405100000`) invece di creare una tabella dedicata. Una initiative = riga in `loomx_projects` con `type='internal'` e `short_name` = slug initiative. I GTD item si legano via `loomx_item_projects` (N:N gia' esistente).

**Divergenza vs richiesta Loomy:** la richiesta originale chiedeva colonne `owner_agent` + `sponsor_agent`. L'attuale schema ha solo `agent_id` (responsabile). Mappiamo `owner_agent → agent_id`, sponsor inserito in `notes`. Se il dual ownership diventa load-bearing, follow-up per ALTER TABLE.

**Conseguenze:**
- Migration `20260406030000_loomx_initiative_rls_security.sql` inserisce la prima initiative `rls-security` + lega 6 GTD item
- Niente nuova tabella per initiatives → schema piu' semplice, costi cognitivi minori
- Eventuale evoluzione: aggiungere `sponsor_agent` se serve filtrare/visualizzare per sponsorship

### D-011 — RLS Phase 1: gate gap empirici prima della migration `agents`
**Tags:** rls, security, governance
**Data:** 2026-04-06

In risposta a D-019/D-020 (Loomy), la Fase 1 RLS (POC Doc dockerizzato) non parte con una migration unica. Ordine vincolante:
1. Setup staging schema `agents_staging` (richiede sblocco CLI/dashboard — vedi blocker §5 di `RLS_PHASE1_PLAN.md`)
2. **Gap A** Supavisor session mode 10 ruoli concorrenti — test anti-leak
3. **Gap B** REVOKE `pg_stat_activity` vs Supabase Studio managed
4. **Gap C** Setup Docker base + `bw unlock` end-to-end
5. SOLO se i 3 gap passano → migration `agents` schema + ruolo `doc_researcher` (bozza in `RLS_PHASE1_PLAN.md` §3)
6. Dockerfile completo + `agent_manager.py` Docker-aware
7. POC reale 1 settimana di uso da Achille

**Conseguenze:**
- Nessuna migration `agents` viene scritta come file finche' i gap non sono chiusi (evita migration bruciate da rework)
- Plan operativo dettagliato in `docs/RLS_PHASE1_PLAN.md`
- Blocker strutturale: `supabase` CLI non installato sull'host DBA → impossibile applicare migration o eseguire test gap autonomamente

---

### D-012 — Supabase CLI installato come binario locale in `~/bin`
**Tags:** tooling, dba
**Data:** 2026-04-06

Installato `supabase` 2.84.2 da release GitHub (`supabase_windows_amd64.tar.gz`) in `~/bin/supabase.exe`. Motivazione: `npm install -g supabase` non supportato (postinstall fallisce), `winget search supabase` non trova il pacchetto. Lo `~/bin` non è in PATH di default — `export PATH="$HOME/bin:$PATH"` all'inizio di ogni sessione operativa che usa il CLI. Da formalizzare in CLAUDE.md o profile bootstrap nelle prossime sessioni.

### D-013 — Bitwarden CLI personal API key blocker (S007)
**Tags:** security, rls, blocker
**Data:** 2026-04-06

Le credenziali API Bitwarden fornite in `env.local.txt` (BW_CLIENTID `user.<uuid>` 41 char, BW_CLIENTSECRET 30 char, lunghezze coerenti col formato standard) vengono rifiutate da `bw login --apikey` con `client_id or client_secret is incorrect`. CRLF/whitespace già strippati, server `vault.bitwarden.com` impostato. Probabili cause (da verificare con Achille): (a) chiavi rigenerate/invalidate da operazione successiva sul vault, (b) chiavi copiate dal posto sbagliato (organization vs personal). Achille deve regenerare l'API key da vault.bitwarden.com → Account Settings → Security → Keys → API Key → View, e re-incollarla in `env.local.txt`. Fino ad allora gli step 4 (test secret), Gap C (Docker base con bw injection) e step 7 (migration `agents`) restano BLOCCATI. Migration initiative `20260406030000` invece è stata applicata con successo (project_id `929ba96c-1450-452d-9ef8-9d059b4c7090`).

### D-014 — Bitwarden vault region = EU (vault.bitwarden.eu)
**Tags:** security, rls, governance
**Data:** 2026-04-06

L'account Bitwarden di Achille vive sul cluster europeo (`vault.bitwarden.eu`), non su quello US (`vault.bitwarden.com`). I due cluster sono database separati: l'account creato su EU non esiste su US, e viceversa. Razionale: Achille è italiano, account creato in region EU per coerenza GDPR (i dati restano in UE). **Conseguenza operativa:** ogni script/sessione che usa `bw` deve eseguire `bw config server https://vault.bitwarden.eu` PRIMA di `bw login`/`bw unlock`. Questa è la causa root del blocker D-013 (S007): il server era configurato di default su US, dove l'API key personale di Achille non era valida perché l'utente non esiste lì. Sblocco confermato in S008. D-013 va considerata superseded.

### D-009 — Utente auth dedicato per garmin_fetch.py (no service_role)
**Tags:** security, home, rls
**Data:** 2026-04-06

Lo script `garmin_fetch.py` si autentica con un utente Supabase dedicato (`garmin-sync@loomx.local`) tramite `supabase-py` client, **non** con service_role key. RLS policies su `home_garmin_health` concedono solo SELECT/INSERT/UPDATE a quell'email. Nessuna policy su altre tabelle → zero accesso altrove. DELETE negato implicitamente (deny-all). L'utente auth viene creato via Supabase Admin API (non via SQL migration) perché lo schema `auth` ha trigger interni che devono eseguire. Migrazione: `20260406020000_home_garmin_health_rls_sync_user.sql`.

---

### D-015 — `supabase db query --linked` come canale operativo SQL headless DBA
**Tags:** tooling, dba, rls
**Data:** 2026-04-06

Scoperto in S009. Il sub-comando `supabase db query --linked [-f file.sql]` esegue SQL arbitrario sul progetto linkato passando per la Management API (HTTPS), senza richiedere `psql` né conoscere la DB password. Sblocca tutti i test di gap, setup staging, ispezione catalog ad-hoc dall'host DBA che non ha psql installato. Output JSON con boundary anti-prompt-injection quando `--agent yes`. Questo diventa il canale standard per l'esecuzione SQL headless del DBA, accanto a `supabase db push --linked` (riservato a migration files versionati). **Privilegi**: gira come `postgres` user del progetto, NON come `supabase_admin` — vedi limitazione D-016.

### D-016 — Hardening 4.5 (REVOKE pg_stat_*) NON implementabile su Supabase managed
**Tags:** rls, security, blocker, governance
**Data:** 2026-04-06

Empiricamente verificato in S009 (Gap B test). Tentativi:
1. `REVOKE SELECT ON pg_catalog.pg_stat_activity FROM <agent_role>` → no-op silente. Causa: PUBLIC ha SELECT, il ruolo agente eredita da PUBLIC.
2. `REVOKE SELECT ON pg_catalog.pg_stat_activity FROM PUBLIC` → CLI rc=0 ma `relacl` invariato. Causa root: il GRANT a PUBLIC è di proprietà di `supabase_admin` (ACL: `{supabase_admin=arwdDxtm/supabase_admin,=r/supabase_admin}`); PostgreSQL impone che solo il grantor (o membro della sua role) possa revocare. L'utente `postgres` esposto da Supabase managed NON è membro di `supabase_admin` → la REVOKE è no-op silente.

**Conseguenza:** l'hardening 4.5 di RLS_DECISIONE_SICUREZZA come scritto non è implementabile dal DBA del progetto. Piano RLS Phase 1 da emendare. Mitigazioni residue verificate empiricamente:
- Filtro nativo Postgres: `query` text di altre connessioni mostrato come `<insufficient privilege>` ai non-superuser (test: 13 hidden / 1 visible).
- `pg_stat_statements`: relation non raggiungibile dai ruoli agente (extension schema fuori dal search_path) → denied di fatto.
- **Leak residuo non eliminabile**: `usename`, `datname`, `application_name`, `client_addr`, `state`, `wait_event` di altre connessioni → enumerazione ruoli attivi + metadati sessione.

**Opzioni di rimedio (da decidere con Loomy/Achille):**
- B-opt-1: ticket Supabase support per REVOKE a livello supabase_admin (esito incerto su plan Free).
- **B-opt-2 (preferito DBA)**: accettare il residuo, neutralizzare l'enumerazione con nomi-ruolo opachi (`agt_a8f3kx_doc` invece di `doc_researcher`), forensics via pgaudit + log shipping S3.
- B-opt-3: rimuovere 4.5 dalla lista hardening obbligatori, amendment esplicito a D-019 (Loomy DECISIONS).

### D-017 — Container agente: Design C (host-side secret extraction) + master prompt-on-demand
**Tags:** rls, security, docker, vault
**Data:** 2026-04-07

Decisione presa in S011 cont. dopo che la POC RLS Phase 1 ha messo davanti la domanda concreta: come passa la password DB dell'agente al suo container in modo che (a) la master Bitwarden non viva su disco e (b) il blast radius del container resti limitato al singolo segreto operativo del ruolo.

**Design scelto: C — host-side secret extraction.**

1. **Solo l'host parla con Bitwarden.** Il launcher (`hub/agent_manager.py`, lavoro Loomy) sull'host fa unlock vault, fetch della password DB del ruolo (es. `loomx/agents/doc_researcher`), lock vault.
2. **Il container è cieco al vault.** Riceve un singolo env var `DB_PASSWORD`, scrive `.pgpass` in tmpfs (`/runtime`), esegue `claude` (o `psql` smoke). Niente `bw` CLI nel container, niente API key, niente master.
3. **Master password mai su disco.** Il launcher prompta interattivamente via `getpass()` ogni volta che serve unlock. La master vive nella RAM del processo Python il tempo necessario per ottenere `BW_SESSION`, poi viene scartata.

**Perché Opt 1 (prompt-on-demand) e non cache della session:**
- Achille ha rifiutato esplicitamente il salvataggio di `BW_SESSION` su file dopo discussione sul threat model: anche un file 600 in `~/.loomx/.bw-session` resta "qualcosa che decifra il vault" finché esiste, e su un PC dentro OneDrive sincronizzato non è abbastanza protetto.
- Costo: ogni invocazione di un agente containerizzato richiede prompt master. Per uso normale (Doc invocato sporadicamente) accettabile.
- Possibile evoluzione futura: cache short-TTL fuori OneDrive, riaperta come decisione separata se l'attrito Opt 1 diventa eccessivo.

**Conseguenze applicate in S011 cont.:**
- `env.local.txt` ora contiene SOLO `BW_CLIENTID` + `BW_CLIENTSECRET` (API key, da sole non decifrano il vault). `BW_PASSWORD` rimosso. Memoria locale `env_local_relocation_todo` per l'eventuale spostamento del file fuori OneDrive in futuro.
- `docker/doc-researcher/entrypoint.sh` semplificato: rimosso tutto il blocco `bw config/login/unlock/get item`, ora accetta `DB_PASSWORD` come env required, scrive `.pgpass` in tmpfs ed esegue.
- `docker/doc-researcher/Dockerfile` snellito: rimosso `bw`, `unzip`, `jq` (non più necessari). Image scesa da ~640 MB a 571 MB.
- `loomx/doc-researcher:poc` ricostruita e validata con `SMOKE=1` (struttura) e `SMOKE_LIVE=1` (connessione reale al pooler EU come `doc_researcher`, master digitata interattivamente in Git Bash via `read -s` da Achille).
- Spec per il launcher in `docs/AGENT_MANAGER_DOCKER_SPEC.md` consegnata a Loomy come riferimento per implementare GTD `db896a84`.

**Threat model in chiaro:**
- Compromesso laptop con file system access → attaccante vede `BW_CLIENTID/SECRET` (inerti senza master) + immagine Docker (no secrets at rest) + eventuali env del processo Python in esecuzione (master solo se beccato proprio al momento del prompt, finestra brevissima). Il vault NON è decifrabile.
- Compromesso container in esecuzione → attaccante vede solo `DB_PASSWORD` di `doc_researcher`, che è RLS-locked (può fare quello che la policy permette al ruolo, niente di più). Niente accesso ad altri ruoli, niente master, niente API key.
- Compromesso OneDrive (file in cloud Microsoft) → vede `env.local.txt` con la sola API key, inerte. (Master era stata in OneDrive fino al 2026-04-07 in `env.local.txt`, ora rimossa — debito tecnico chiuso.)

**Azioni correlate:**
- Achille deve **ruotare la master Bitwarden** (vault.bitwarden.eu → Account Settings → Security) entro fine giornata 2026-04-07: la vecchia è stata letta dal DBA durante l'edit del file in S011 cont. e quindi è transitata nel context window di una sessione AI. Anche se Anthropic non addestra su user data, igiene di sicurezza vuole rotation.
- Quando D-018 (`loomx_item_agents`) sarà implementato, la policy RLS di `doc_researcher` (e di tutti i ruoli Fase 2) andrà estesa per supportare co-engagement. Non bloccante per Fase 1.

---

*Watermark: D-017*
