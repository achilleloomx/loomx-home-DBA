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

### D-018 — `loomx_item_agents`: co-engagement N:N item↔agente
**Tags:** rls, governance, gtd
**Data:** 2026-04-07

Implementazione locale del concetto D-018 di Loomy (hub): un item GTD può avere più agenti "ingaggiati" senza forzarli nei due campi singoli `owner` / `waiting_on`. Necessario per generalizzare le policy RLS per-agente in vista del rollout Fase 2 (D-020) ai 9 agenti rimanenti — finché non c'è co-engagement esplicito, gli agenti vedono solo righe di cui sono owner o waiting_on diretti, e qualunque task collaborativo serio rompe.

**Schema** (migration `20260407130000`):
```sql
CREATE TABLE loomx_item_agents (
  item_id    UUID NOT NULL REFERENCES loomx_items(id)    ON DELETE CASCADE,
  agent_slug TEXT NOT NULL REFERENCES board_agents(slug) ON DELETE CASCADE,
  role       TEXT NOT NULL DEFAULT 'collaborator',
  added_by   TEXT NOT NULL,
  added_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (item_id, agent_slug)
);
CREATE INDEX loomx_item_agents_agent_slug_idx ON loomx_item_agents (agent_slug);
ALTER TABLE loomx_item_agents ENABLE ROW LEVEL SECURITY;
```

**Divergenza dalla proposta Loomy**: la FK su `agent_slug` punta a `board_agents(slug)` (UNIQUE confermata), NON a `loomx_agents(slug)` — quest'ultima tabella non esiste nello schema corrente. La rubrica unica degli agenti è `board_agents` (D-001), nessun motivo per duplicarla.

**Policy estensione doc_researcher** (migration `20260407140000`): drop+recreate (non ALTER POLICY in-place) di `doc_researcher_select_engaged` e `doc_researcher_update_engaged`. Le nuove USING/WITH CHECK accettano:
1. `owner = 'researcher'` (caso originale)
2. `waiting_on = 'researcher'` (caso originale)
3. `EXISTS (SELECT 1 FROM loomx_item_agents WHERE item_id = loomx_items.id AND agent_slug = 'researcher')` (NUOVO)

`doc_researcher` ottiene anche `SELECT` su `loomx_item_agents` filtrato dal proprio slug (policy `doc_researcher_select_own_links`) — gli serve per sapere "in quali item sono co-engaged". NON ottiene INSERT/UPDATE/DELETE: la gestione dei link è prerogativa di Loomy/service_role o dei tool MCP che Postman aggiungerà in iterazione successiva.

**Test funzionali (9/9 PASS)** via `psycopg2` come `doc_researcher`, eseguiti in S011 cont. tramite `.scratch/d018_test.sh`:
- Setup item con `owner='researcher'` → ALLOW
- Setup item con `owner='dba'` (spoof) → DENY
- Item foreign (creato via service_role) → invisibile prima del link
- Link via service_role → item ora visibile
- UPDATE foreign item via co-engagement → ALLOW
- UPDATE owner='dba' mentre co-engaged → ALLOW (semanticamente OK: finché c'è il link, l'agente può modificare; se la membership viene rimossa, perde l'accesso alla riga modificata)
- SELECT su `loomx_item_agents` → vede solo i propri link
- INSERT su `loomx_item_agents` → DENY (no GRANT)
- Dopo unlink → torna invisibile

**Open item delegato a Postman/board-mcp**: il Board MCP attualmente NON ha tool per gestire co-engagement (`gtd_link_agent` / `gtd_unlink_agent` o simili). Per ora la membership si gestisce solo via service_role. Loomy ha confermato che aprirà un GTD a Postman per aggiungere i tool quando servono.

**Generalizzazione Fase 2**: ogni nuovo ruolo per-agente (Fase 2 D-020) avrà policy RLS modellate su questo pattern. Lo slug literal (`'researcher'`) va parametrizzato per ogni agente — non si può usare una function generica `current_agent_slug()` perché `session_user` è già il discriminante e mappare role → slug richiederebbe una lookup table o configurazione. Più semplice: una migration per agente.

---

### D-019 — Approccio Docker per Doc: SOSPESO. Fase 1 RLS prosegue host-direct con ruolo dedicato.
**Tags:** rls, docker, governance, deferral
**Data:** 2026-04-07

**Decisione presa in S011 cont. ³** dopo che il primo test reale di `agent_manager.py invoke researcher "..."` ha rivelato un blocker non risolvibile dentro il perimetro DBA: claude all'interno del container risponde `Not logged in · Please run /login`. Il container parte vergine, senza stato OAuth Claude Max.

**Opzioni esaminate per sbloccare il container:**

1. **`ANTHROPIC_API_KEY` via env** — pulito, container resta stateless. **Scartato**: Achille usa Claude Max OAuth, le API key sono un canale di billing separato (non incluso nell'abbonamento Max), non è un'opzione operativa né economica.
2. **Bind mount `~/.claude/.credentials.json`** — l'unica strada tecnica per riusare l'OAuth dell'host nel container. **Scartato per peso/rischio**:
   - Concurrent session: lo stesso refresh token usato in 2 processi contemporaneamente (host attivo + container) potrebbe innescare rate limit, invalidazione o richiesta di re-login lato Anthropic. Comportamento non documentato pubblicamente, rischio empirico non quantificabile a priori.
   - Write race sul refresh token (claude del container può aggiornarlo nello stesso file che claude dell'host sta usando).
   - File permission cross-platform Windows host → Linux container (uid 1000 `node`).
   - `.credentials.json` è il segreto più pesante della catena (accesso completo al sub Claude Max), bind mount in container amplia la superficie di attacco.
3. **`claude /login` interattivo dentro container** — non automatizzabile (browser + verification code), e tmpfs `/runtime` perde lo stato a ogni `--rm`. Non praticabile.
4. **Sospendere il container e tenere solo la separazione a livello DB** — Achille ha chiesto esplicitamente di non aggiungere altra struttura. **Scelta**.

**Cosa resta valido di S011 cont. (NON regredisce):**

- Schema `agents` + ruolo `doc_researcher` LOGIN NOINHERIT NOBYPASSRLS (migration `20260407100000`, applicata).
- 4 policies RLS keyed su `session_user` su `loomx_items` e `board_messages` (inclusa estensione D-018).
- `loomx_item_agents` + co-engagement (migration `20260407130000`+`20260407140000`, applicate).
- Test funzionali 10/10 + 9/9 PASS, validati in S011 e S011 cont. ².
- Image `loomx/doc-researcher:poc` rebuildable, Dockerfile + entrypoint Design C committati come artefatti.
- Spec `docs/AGENT_MANAGER_DOCKER_SPEC.md` come riferimento implementativo riusabile (marcato DEFERRED).
- Vault item `loomx/agents/doc_researcher` (Bitwarden EU, secure note `b664040d-...`) — usabile come connection password ovunque, non solo dentro container.

**Cosa è stato revertito:**

- `00. LoomX Consulting/hub/agent_manager.py` riportato allo stato pre-S011 cont. ³ (rimosso `runtime`/`docker` su `Agent`, rimossa config docker di `researcher`, rimossi `_fetch_db_password_from_vault` e `_invoke_docker`, rimossi dispatcher in `cmd_invoke` e `cmd_invoke_interactive`). Diff zero rispetto all'originale, verificato via `ast.parse`.

**Cosa serve fare adesso per chiudere Fase 1 RLS senza container:**

1. **[Loomy]** Aggiornare `hub/researcher/.mcp.json` (o equivalente di Doc) per usare la connection string Postgres con user `doc_researcher.fvoxccwfysazwpchudwp` e password presa da Bitwarden vault item `loomx/agents/doc_researcher`. Il pattern di iniezione (env var, file 600 fuori OneDrive, o altro) è scelta di Loomy.
2. **[Achille]** Lavorare 1 settimana con Doc che parla a Supabase via il ruolo `doc_researcher` (RLS in vigore) e segnalare se incappa in falsi positivi (cose che dovrebbe poter fare e non riesce) o lacune (cose che riesce a fare e non dovrebbe). Questo è il vero test della Fase 1.
3. **[DBA]** Se la settimana regge senza incidenti, preparare la matrice "agente×tabella×permessi" per i 9 agenti di Fase 2 (D-020) e iniziare il rollout dei ruoli (non dei container).

**Quando potrebbe tornare il container:**

- Quando Anthropic rilascerà OAuth machine-friendly per Claude Code (token long-lived gestibili headless).
- Quando si va su VPS Hetzner (D-020 Fase 4): in quel contesto API key Anthropic ha senso (always-on, no UI), e la spec resta valida modulando l'env del launcher.

D-017 (Design C, host-side secret extraction) **resta valida** come pattern per la separazione DB e per il vault handling. La sospensione D-019 riguarda solo il livello "container per claude", non il livello "ruolo Postgres dedicato per agente".

GTD `db896a84` (`agent_manager.py` docker-aware) chiuso come `cancelled` con riferimento a questa decisione.

---

### D-023 — Board MCP backend dual: PostgREST (default) + pg diretto via `DATABASE_URL` (opt-in)
**Tags:** rls, mcp, security
**Data:** 2026-04-07

**Contesto.** Il Board MCP server (`loomx-board-mcp`) e' un processo Node che si autentica via `SUPABASE_SERVICE_ROLE_KEY` → client `supabase-js` → PostgREST. Questo canale **bypassa RLS** per design. Il ruolo Postgres nativo `doc_researcher` (creato per RLS Phase 1, D-017/D-019) vive invece sul canale Supavisor session mode porta 5432, raggiungibile solo da client `pg` diretto. I due canali non si parlano: finche' Doc (researcher) invoca il Board MCP standard, continua a passare per PostgREST+service_role e RLS non e' applicata — anche se lato DB il ruolo esiste ed e' corretto.

**Alternative escluse.**
- **PostgREST + JWT custom con claim `role: doc_researcher`**: richiede `GRANT doc_researcher TO authenticator`, sporca il grafo ruoli Supabase; il Board MCP dovrebbe comunque cambiare per firmare JWT per-agent; pgaudit loggerebbe `authenticator` come session_user, indebolendo B-opt-2; perderebbe senso la separazione di processo (container) che era valore di D-019.
- **psycopg2 diretto dal codice agente**: frammenta l'interfaccia (Doc avrebbe due canali MCP vs DB), rompe l'astrazione "gli agenti parlano solo col Board MCP".
- **Secondo Board MCP dedicato agli agenti RLS-enabled**: code duplication inutile.

**Decisione.** Estendere il Board MCP server con un secondo backend database basato su `pg` (node-postgres), selezionato in base alla presenza di `DATABASE_URL` in env:
- `DATABASE_URL` presente → backend `pg`, connessione diretta via Supavisor session mode 5432. `session_user` = ruolo Postgres nativo dell'agente. RLS attiva. pgaudit logga il ruolo reale.
- `DATABASE_URL` assente → fallback `supabase-js` + `SUPABASE_SERVICE_ROLE_KEY` (comportamento attuale). Nessuna regressione per gli agenti pre-Fase-2.

La superficie tool MCP (`gtd_*`, `board_*`, `loomx_*`) resta identica: la traduzione SQL e la propagazione degli error code devono essere preservate perche' i client esistenti non si accorgano del cambio di backend.

**Regole anti credential-leak** (stesse di `agent_manager.py`, D-017):
- `DATABASE_URL` letto SOLO da env var, mai da argv, mai in log.
- Nel container di Doc esportiamo SOLO `DATABASE_URL` — niente `SUPABASE_SERVICE_ROLE_KEY` — per rendere impossibile un downgrade silente a service_role.

**Owner implementazione:** Postman (agent 005, board-mcp). Task aperto da Loomy prima di questa risposta.
**Review:** il DBA fa review della spec prima del merge, non blocca la feature branch.

**Dipendenza con Fase 1.** La POC settimana di Doc (GTD `5919d745`, cavia RLS Phase 1) parte SOLO dopo che il Board MCP supporta `DATABASE_URL`. Altrimenti la POC misurerebbe il canale sbagliato (service_role via PostgREST) e non validerebbe ne' RLS Phase 1, ne' isolamento di processo, ne' B-opt-2 (pgaudit).

---

*Watermark: D-023*
