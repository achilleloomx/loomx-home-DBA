# HISTORY — LoomX Home DBA

> Storico sessioni del Database Administrator.

---

## S013 — 2026-04-07 (notte) — Review branch feat/direct-postgres-backend di Postman: code review + fix, build OK, test live BLOCCATO (vault)

**Trigger:** task Loomy `9d8ca052` — Postman ha implementato D-023 nel branch `feat/direct-postgres-backend` del repo `loomx-board-mcp` ma non ha potuto eseguire i 7 test live. Richiesto: review, test con ruolo `doc_researcher`, merge se PASS.

### Fatto
1. **Checkout branch** `feat/direct-postgres-backend` — nota: le modifiche sono uncommitted nel working tree del repo di Postman (branch locale senza commit sopra master). Review eseguita sul working tree.
2. **Code review** `src/pg-shim.ts` + `src/supabase.ts`:
   - Identifier regex validation OK (`/^[a-zA-Z_][a-zA-Z0-9_]*$/`), values parametrizzate → no SQL injection.
   - Nessun log credenziali: solo nome backend su stderr.
   - Backwards-compat totale (fallback `SUPABASE_URL`+`SERVICE_ROLE_KEY`).
3. **3 spec violations trovate e corrette sul branch** (fix DBA, da committare quando si riprende):
   - `pg-shim.ts:326` pool senza `max` → settato `max: 5` (spec D-023 §3).
   - `supabase.ts:initClient` preferiva silenziosamente `DATABASE_URL` quando entrambe presenti → ora throw esplicito `"Conflicting DB credentials..."`.
   - Nessuna verifica identita' all'avvio → aggiunto metodo `PgShimClient.verifyIdentity()` che legge `SELECT current_user, session_user` e logga su stderr, invocato fire-and-log in `initClient`.
4. **Build**: `npm install && npm run build` → tsc clean, zero errori.

### Bloccante
- **7 step test live non eseguiti**: sessione lanciata via `agent_manager invoke dba` → no TTY per `bw unlock` in foreground. `env.local.txt` contiene solo `BW_CLIENTID`/`BW_CLIENTSECRET`, non la master. Serve Achille per sbloccare il vault e fornire `BW_SESSION` oppure direttamente la password `doc_researcher`.
- Merge rimandato a quando i 7 test passano.

### Aperti
- Test live 7 step + commit fix pg-shim/supabase + merge master + summary con commit hash → waiting_on=achille per vault unlock.
- Working tree `loomx-board-mcp` ha modifiche uncommitted (branch `feat/direct-postgres-backend` locale di Postman + fix DBA). Da committare alla ripresa con message separato: `fix(pg-shim): pool max=5, conflict error, verifyIdentity (DBA review)`.

---

## S012 — 2026-04-07 (sera) — Gap .mcp.json: Board MCP bypassa RLS, D-023 backend dual pg+PostgREST

**Trigger:** question urgente di Loomy (`ad945246`) aprendo `hub/researcher/.mcp.json` per action del summary 51f7dd5c: il Board MCP usa `SUPABASE_SERVICE_ROLE_KEY` → PostgREST, bypassa RLS. Il ruolo `doc_researcher` (D-017/D-019) vive sul canale Supavisor 5432 e non e' raggiungibile dal Board MCP attuale.

### Fatto
1. **Confermato gap** a Loomy. Mea culpa: nel summary 51f7dd5c avevo proiettato erroneamente il canale psycopg2 (che uso da CLI) su Doc, che invece parla solo col Board MCP Node.
2. **Valutate 4 alternative** (risposta a Loomy, ref `84d369a2`): (a) PostgREST+JWT custom con claim role → scartata per impatto su authenticator grants, firma JWT per-agent, degrado pgaudit; (b) psycopg2 diretto dal codice agente → scartata perche' frammenta l'interfaccia MCP; (c) secondo Board MCP dedicato → code duplication; (d) estensione del Board MCP con backend `pg` opzionale via `DATABASE_URL` backwards-compat → **scelta**.
3. **D-023 scritta** in `docs/DECISIONS.md`: Board MCP backend dual, `DATABASE_URL` opt-in con fallback service_role, regole anti credential-leak (env only, mai argv/log), Postman owner implementazione, DBA review pre-merge, POC Doc bloccata fino al supporto `DATABASE_URL`.
4. **Attesa spec Postman** da Loomy per review (verifico: invarianza tool gtd_*/board_* lato schema, preservazione error code PostgREST→pg, regola env-only).

### Aperti
- Task b45ea879 (implementazione `agent_manager.py` docker-aware + D-018 `loomx_item_agents`) rimandato a sessione dedicata su istruzione Loomy.
- Review spec Board MCP backend dual: in attesa da Loomy/Postman.

---

## S011 cont. ³ — 2026-04-07 (sera) — Container Doc SOSPESO (D-019), Fase 1 prosegue host-direct

**Trigger:** primo test reale di `python hub/agent_manager.py invoke researcher "..."` con il dispatcher docker appena scritto.

### Fatto
1. **Modifiche a `00. LoomX Consulting/hub/agent_manager.py`** (cross-repo, autorizzato da Achille opzione A): aggiunto campo `runtime`/`docker` a `Agent`, config docker per `researcher`, helper `_fetch_db_password_from_vault` (master via getpass, unlock vault, fetch secure note, lock, scrub), helper `_invoke_docker` (docker run con `DB_PASSWORD` via env name only), dispatcher in `cmd_invoke` e `cmd_invoke_interactive`. `_which()` per risolvere `bw`/`docker` come `.cmd` shim su Windows (Python `subprocess` su Windows non risolve PATH come bash).
2. **Test live**: container parte, vault unlock OK, DB password fetched, entrypoint exec `claude --print --dangerously-skip-permissions <preambolo+prompt>`. **claude dentro al container risponde `Not logged in · Please run /login`**. Container vergine, OAuth state non presente.
3. **Analisi opzioni** (vedi D-019 per dettaglio): API key Anthropic scartata (Claude Max OAuth obbligatorio), bind mount `.credentials.json` scartato (concurrent session risk + write race + secret pesante), `/login` interattivo non praticabile.
4. **Decisione di Achille** dopo discussione threat model: **sospendere l'approccio Docker** per Doc, tenere il valore di sicurezza al livello DB (ruolo `doc_researcher` + RLS) che è già completo.
5. **Revert `agent_manager.py`** all'originale via Edit (il repo Consulting non è git, niente checkout possibile). Verifica via `ast.parse` + `python list`: 7 funzioni come l'originale, nessun residuo docker, sintassi OK.
6. **D-019 scritta** in `docs/DECISIONS.md` con racconto opzioni esaminate, scelte, cosa resta valido, cosa fare adesso per chiudere Fase 1 senza container.
7. **`docs/AGENT_MANAGER_DOCKER_SPEC.md` marcato DEFERRED** in header, resta come riferimento riusabile.
8. **GTD `db896a84` (agent_manager docker-aware)** sarà chiuso come `cancelled` (lo faccio dopo il commit).
9. **Summary completo a Loomy** con consegnabili Fase 1 senza container e palla per `hub/researcher/.mcp.json`.

### Cosa resta in piedi (NON regredisce)
- Schema agents + ruolo `doc_researcher` (live, RLS chirurgica)
- D-018 `loomx_item_agents` + co-engagement (live, 9/9 PASS)
- Image `loomx/doc-researcher:poc` come artefatto (rebuildable, futura)
- Vault item Bitwarden `loomx/agents/doc_researcher` come connection password riusabile

### Cosa serve adesso per chiudere Fase 1
- **Loomy**: aggiornare `hub/researcher/.mcp.json` (o equivalente Doc) per Postgres user `doc_researcher.fvoxccwfysazwpchudwp` con password dal vault.
- **Achille**: 1 settimana di uso reale Doc con ruolo dedicato → segnalare falsi positivi o lacune RLS.
- **DBA**: se la settimana regge, matrice agente×tabella×permessi per Fase 2 e rollout dei ruoli (non dei container) ai 9 agenti rimanenti.

### Lezione strutturale
Il container per claude code è incompatibile con OAuth desktop senza compromessi pesanti. La separazione a livello DB (D-017 Design C, ruolo per agente, RLS) **da sola fornisce il 90% del valore di sicurezza** che il piano D-019 originale (Loomy) cercava. Il container è ortogonale e si reinserisce quando l'auth machine-friendly esiste o quando si va su VPS con API key separata.

---

## S011 cont. ² — 2026-04-07 (tardo pomeriggio) — D-018 loomx_item_agents applicato, 9/9 PASS

**Trigger:** msg `b45ea879` (Loomy → DBA, 15:40): GO su 2 fronti, (1) implementa `agent_manager.py` docker-aware, (2) design+apply `loomx_item_agents` in autonomia. Achille conferma: prima D-018 (puro SQL, niente cross-repo), poi `agent_manager.py` cross-repo.

### Fatto (parte D-018)
1. **Verifica schema esistente**: `loomx_agents` non esiste, `board_agents` sì con `slug` UNIQUE — userò questa come target FK (divergenza giustificata dalla proposta Loomy).
2. **Migration `20260407130000_loomx_item_agents.sql`** — schema PK composto, FK CASCADE, index su agent_slug, RLS deny-all.
3. **Migration `20260407140000_doc_researcher_co_engagement.sql`** — drop+recreate delle policy `doc_researcher_select_engaged` e `doc_researcher_update_engaged` con OR EXISTS su `loomx_item_agents`. Nuova policy `doc_researcher_select_own_links` su `loomx_item_agents` (filtrata da slug). GRANT SELECT only.
4. Dry-run combinato delle 2 migration → PASS.
5. Apply via `supabase db query --linked` → entrambe applicate.
6. Test funzionale via `.scratch/d018_test.sh`: master Bitwarden digitata da Achille in Git Bash, fetch DB password, psycopg2 come `doc_researcher` + setup admin via `supabase db query` per le righe foreign. **9/9 PASS**:
   - Setup item own=researcher OK
   - Setup item owner=dba (spoof) DENY
   - Foreign item invisibile prima del link
   - Foreign item visibile dopo INSERT in loomx_item_agents
   - UPDATE foreign item via co-engagement ALLOW
   - UPDATE owner='dba' while co-engaged ALLOW (semanticamente OK)
   - SELECT loomx_item_agents filtrato
   - INSERT loomx_item_agents DENY
   - Foreign item invisibile dopo unlink
7. **D-018 scritta** in `docs/DECISIONS.md` (locale).
8. **Cleanup test rows** via service_role (transient 500 della Management API al primo tentativo, OK al retry).

### Note D-018
- Tool MCP per gestire co-engagement (`gtd_link_agent`/`gtd_unlink_agent` o simili) NON esistono ancora — la membership va gestita via service_role o lo aggiunge Postman in iterazione successiva. Loomy avvisato.
- Pattern generalizzabile per Fase 2: ogni nuovo ruolo per-agente avrà policy RLS modellate su questo, una migration per agente. Lo slug literal va parametrizzato per ogni ruolo (non function generica perché `session_user` è già il discriminante e una lookup table farebbe più male che bene).
- Bloccante per Fase 2 RLS rollout dei 9 agenti: **rimosso**.

### Da fare ancora in S011 cont. ²
- Implementare `agent_manager.py` docker-aware in `00. LoomX Consulting/hub/agent_manager.py` (cross-repo, autorizzato da Achille opzione A).
- Summary unico a Loomy a fine sessione con entrambi i fronti (D-018 + agent_manager).
- Commit + push.

---

## S011 cont. — 2026-04-07 (pomeriggio) — Container Doc → Design C, master prompt-on-demand

**Trigger:** GTD `db896a84` da Loomy (creato 09:43): `agent_manager.py` deve diventare docker-aware per slug `researcher`. Il GTD originale prevedeva di iniettare credenziali Bitwarden nel container; rivisto in sessione su input di Achille per ridurre il blast radius.

### Fatto
1. **Discussione threat model + scelta Design C** (vedi D-017): solo l'host parla con Bitwarden, il container è cieco al vault, riceve `DB_PASSWORD` e basta. Master prompt-on-demand (Opt 1, no cache session su disco).
2. **`env.local.txt` ripulito**: rimossa `BW_PASSWORD`, restano solo `BW_CLIENTID` + `BW_CLIENTSECRET` (API key, inerti senza master). File da 144 → 103 byte. Memoria locale `env_local_relocation_todo` per ricordarsi lo spostamento del file fuori OneDrive in sessione futura.
3. **`docker/doc-researcher/entrypoint.sh` semplificato** (Design C): rimosso tutto il blocco `bw config/login/unlock/get item`. Ora richiede `DB_PASSWORD` come env, scrive `.pgpass` in tmpfs, esegue. Modi `SMOKE=1` (struttura, no DB) e `SMOKE_LIVE=1` (connessione reale al pooler) entrambi mantenuti.
4. **`docker/doc-researcher/Dockerfile` snellito**: rimosso `bw`, `unzip`, `jq` (non più necessari). Restano `psql`, `python3`, `claude`, `ca-certificates`. Image scesa da ~640 MB a **571 MB**.
5. **Rebuild `loomx/doc-researcher:poc`** OK.
6. **Smoke validation completa**:
   - `SMOKE=1` (no DB) PASS dall'host: tutte le tool dentro il container OK, `node v20.20.2`, `psql 15.16`, `python 3.11.2`, `claude 2.1.92`, `RUNTIME_DIR=/runtime` (700 node).
   - `SMOKE_LIVE=1` PASS via script `.scratch/smoke_live.sh` lanciato da Achille in Git Bash. Achille ha digitato la master interattivamente (`read -s`, mai in chat), il script ha fatto unlock vault, fetch DB password, lock, lanciato il container con `DB_PASSWORD` env, ottenuto:
     ```
     [entrypoint] SMOKE_LIVE: connecting via Supavisor session-mode
     session_user=doc_researcher current_user=doc_researcher
     [entrypoint] smoke_live OK
     ```
   - Validato sul campo: master mai in chat, mai su disco, container zero footprint Bitwarden.
7. **Spec per Loomy**: `docs/AGENT_MANAGER_DOCKER_SPEC.md` — guida implementativa completa per il GTD `db896a84` (`hub/agent_manager.py` lato Loomy nel suo repo). Include pseudo-codice, criteri di accettazione, regole anti credential-leak, lista negativa.
8. **D-017 scritta** in `docs/DECISIONS.md` (Design C + Opt 1 + threat model in chiaro + azione di rotation master richiesta ad Achille).

### Note
- **Master Bitwarden esposta nel context window**: per editare `env.local.txt` e rimuovere `BW_PASSWORD` ho dovuto leggere il file. La master è quindi transitata nella mia sessione AI. Anthropic non addestra su user data ma rotation raccomandata entro fine giornata. **Action item per Achille:** vault.bitwarden.eu → Account Settings → Security → Master Password → cambia.
- D-018 (`loomx_item_agents`, co-engagement) ancora non implementato → policy RLS di `doc_researcher` resta su `owner='researcher' OR waiting_on='researcher'`. Sarà esteso quando D-018 viene implementato (owner Loomy).
- Bug noto Git Bash: `read -s` dentro script paste-multilinea legge la riga successiva del paste come password. Workaround: salvare lo script in un file e lanciarlo (`.scratch/smoke_live.sh`).

---

## S011 — 2026-04-07 — RLS Phase 1 POC Doc end-to-end PASS

**Trigger:** chiusura naturale di S010 (Gap C strutturale ok, migration scritta ma non applicata).

### Fatto
1. **Scoperta correzione storica**: `supabase` CLI 2.84.2 È installato in `~/bin/supabase` (S007). Memoria S010 "no CLI sull'host" era errata. Tutte le migration di questa sessione applicate via `supabase db query --linked`.
2. **Migration leggere applicate** (Step A):
   - `20260407110000_loomx_items_gtd_status_canonical.sql` — drop+recreate `loomx_items_gtd_status_check` con set canonico AGENT-STANDARD §5: `inbox, next_action, waiting, scheduled, in_progress, someday, done, trash`. Data migration `waiting_for→waiting`, `calendar→scheduled`, `project_task→next_action`. View `loomx_v_waiting_for` riallineata. Verificato: `gtd_update c8e7da72 → in_progress` ora PASS. GTD chiuso.
   - `20260407120000_home_school_menu_exclusions.sql` — tabella separata (non colonna su `home_school_menus`) per exclusions scraper menu Azzurra, RLS family-based, GRANT authenticated, `reason TEXT` libero (tassonomia lato app). Notificato 003/app (msg `13f67492`). Notificato Postman per allineamento enum lato MCP server (msg `21efaa0b`).
3. **Step B — RLS Phase 1 POC Doc full chain live**:
   - **Dry-run** della migration `20260407100000` (BEGIN…ROLLBACK) → trovato bug: policy `doc_researcher_insert_messages` usava `from_agent_slug` (colonna inesistente sulla tabella base — esiste solo nelle view via JOIN). Fixato a `from_agent='021'` (board_messages.from_agent contiene il code agente, researcher=021).
   - **Vault EU sbloccato** via `env.local.txt` (BW_CLIENTID/SECRET/PASSWORD), `bw config server https://vault.bitwarden.eu` (D-014), unlock non interattivo.
   - **Password ruolo** `doc_researcher` generata 32 char alfanum con `bw generate -uln`, salvata come **Secure Note** `loomx/agents/doc_researcher` in collection Agents (org LoomX Consulting). Item id `b664040d-8c64-4752-83f1-b4250081eff3`. Convenzione: password = ultima riga del campo `notes`. Mai scritta su disco fuori dal vault.
   - **Migration applicata** sostituendo `__REPLACE_AT_APPLY_TIME__` solo in file temporaneo `/tmp/mig.*.sql` (rimosso subito dopo). Schema `agents` creato, ruolo `doc_researcher` LOGIN NOINHERIT NOBYPASSRLS, GRANT chirurgici, 4 policies RLS keyed su `session_user`. Verificato `pg_namespace`, `pg_roles`, `pg_policy`, `has_table_privilege` — tutto consistente.
4. **Smoke matrice 10/10 PASS** via psycopg2 dall'host contro `aws-1-eu-west-3.pooler.supabase.com:5432` user `doc_researcher.fvoxccwfysazwpchudwp`:

   | # | Test | Atteso | Esito |
   |---|---|---|---|
   | 1 | session_user/current_user | doc_researcher | ✅ |
   | 2 | SELECT board_messages | DENY (no GRANT) | ✅ |
   | 3 | INSERT board_messages from_agent='021' | ALLOW | ✅ |
   | 4 | INSERT board_messages from_agent='002' (spoof) | DENY (RLS) | ✅ |
   | 5 | SELECT loomx_items | ALLOW (RLS filtra) | ✅ |
   | 6 | INSERT loomx_items owner='researcher' | ALLOW | ✅ |
   | 7 | INSERT loomx_items owner='dba' (spoof) | DENY (RLS) | ✅ |
   | 8 | DELETE loomx_items | DENY (no GRANT) | ✅ |
   | 9 | SELECT home_school_menus | DENY (no GRANT) | ✅ |
   | 10 | INSERT board_agents | DENY (no GRANT) | ✅ |

5. **Container Doc — fix entrypoint + smoke live PASS**:
   - 3 bug nell'entrypoint S010 fixati:
     - `bw get password` non funziona su Secure Note → ora estrae da `notes` via `python3 ... rsplit('\n',1)[-1]`.
     - User pooler era `-U doc_researcher` → ora `PG_USER="${AGENT_SLUG}.${SUPABASE_PROJECT_REF}"`.
     - Host pooler era `aws-0-eu-west-3` → corretto a `aws-1-eu-west-3` (S009 confermato).
   - Aggiunto modo `SMOKE_LIVE=1` (vs `SMOKE=1` di S010): esegue tutto il flusso bw + psql verso il pooler e termina senza chiamare `claude`.
   - Rebuild `loomx/doc-researcher:poc`, run con tmpfs `/runtime` + env BW_*: **PASS**:
     ```
     [entrypoint] configuring bw server: https://vault.bitwarden.eu
     [entrypoint] bw login (apikey)
     [entrypoint] bw unlock
     [entrypoint] fetching DB password for loomx/agents/doc_researcher
     [entrypoint] SMOKE_LIVE: running RLS allow/deny matrix
     session_user=doc_researcher current_user=doc_researcher
     [entrypoint] smoke_live OK
     ```
6. **GTD `5919d745` (POC Doc dockerizzato) → done.** Summary completo a Loomy (msg `d015c267`).

### Decisioni / convenzioni emerse (memorie locali)
- `supabase db query --linked` come canale operativo headless DBA (riconferma S009).
- Pooler EU: `aws-1-eu-west-3.pooler.supabase.com`, user format `<role>.<project_ref>`. Non richiede account AWS.
- Vault: password ruoli DB = Secure Note, ultima riga di `notes`. `bw get item` + parse JSON, mai `bw get password`.
- `board_messages.from_agent` contiene il code (`'021'`), non lo slug. Lo slug è derivato solo nelle view.

### Note residue (non bloccanti)
- D-018 `loomx_item_agents` non implementato → policy SELECT/UPDATE di doc_researcher resta su `owner='researcher' OR waiting_on='researcher'` (estensione co-engagement deferred).
- pgaudit non installato sul progetto → blocco DO `ALTER ROLE ... SET pgaudit.log` skipped.
- Audit log shipping S3 (parte log del 4.5 originale) ancora da pianificare separatamente.
- 1 settimana di uso reale Doc dockerizzato (D-019 step 7) prima di Fase 2 rollout 9 agenti — owner Loomy/Achille, non DBA.

---

## S010 — 2026-04-07 — Gap C strutturale PASS + migration agents/doc_researcher scritta

**Trigger:** task Loomy `766edb3d` (sblocco D-021 + Docker installato).

### Fatto
1. **Pre-flight**: letto board_inbox + gtd_inbox + RLS_PHASE1_PLAN.md. GTD `5919d745` non aggiornabile a `in_progress` — `loomx_items_gtd_status_check` non include il valore (mismatch fra enum API e check constraint DB; da fixare in migration successiva).
2. **Docker host check**: `docker run hello-world` OK (Docker 29.3.1).
3. **Gap C — Dockerfile + entrypoint scritti** in `docker/doc-researcher/`:
   - `FROM node:20-bookworm-slim`, riusa user `node` (uid 1000) — niente `useradd` duplicato.
   - Tools: `bw` 2024.10.0 (binario release ufficiale), `psql` 15, `python3`, `claude-code` CLI 2.1.92.
   - `entrypoint.sh`: `bw config server https://vault.bitwarden.eu` PRIMA di login (D-014), `bw login --apikey` + `bw unlock --passwordenv`, fetch password `loomx/agents/doc_researcher` in `$RUNTIME_DIR` (tmpfs), `.mcp.json` generato a runtime e mai committato, `bw lock` + `unset` delle env sensibili prima dell'`exec`.
   - Modalità `SMOKE=1`: stampa diagnostica e termina senza toccare il vault.
4. **Build immagine** `loomx/doc-researcher:poc` OK.
5. **Smoke test** (`SMOKE=1` + tmpfs `/runtime`): tutti i tool presenti, user `node`, exit 0. Output:
   ```
   user=node uid=1000 / node v20.20.2 / bw 2024.10.0 / psql 15.16 / python 3.11.2 / claude 2.1.92
   ```
6. **Migration scritta**: `20260407100000_agents_schema_doc_researcher.sql`.
   - Schema `agents` + REVOKE da public/anon/authenticated.
   - Ruolo `doc_researcher` LOGIN NOINHERIT NOBYPASSRLS, password placeholder `__REPLACE_AT_APPLY_TIME__` (set via Studio dal vault).
   - REVOKE difensivi su public + GRANT chirurgici su `board_messages` (INSERT) e `loomx_items` (SELECT/INSERT/UPDATE filtrati da policy).
   - Policies RLS keyed su `session_user = 'doc_researcher'` (hardening 4.2) + filtro `owner='researcher' OR waiting_on='researcher'` (D-018 placeholder fino a `loomx_item_agents`).
   - REVOKE `pg_stat_statements` condizionale (4.5 parziale, D-021). `pg_stat_activity` NON revocato (descope D-021).
   - `pgaudit.log = 'write,ddl'` condizionale.

### Stato Gap C
- **Strutturale: PASS** (image build, tools, EU config wiring, secrets in tmpfs, non-root, lock).
- **Live end-to-end (bw login + DB connect): PENDING** — bloccante noto `0867882a`: serve master password vault Bitwarden via canale sicuro fuori board. NON è un nuovo gap, è il blocker già censito.

### Non fatto / blocker
- Migration NON applicata: nessun `supabase` CLI sull'host DBA. Passare ad Achille per apply via Studio (con password vera dal vault).
- GTD `5919d745` resta `next_action` finché non si fixa il check constraint.
- Smoke live richiede credenziali Bitwarden.

---

## S009 — 2026-04-06 — Gap A PASS, Gap B FAIL (hardening 4.5 non implementabile)

**Partecipanti:** Achille (via task) + DBA (002). Sessione parallela a S008 (Bitwarden), scope: solo Gap A + Gap B, no Bitwarden/Docker.

### Cosa è stato fatto
1. **Scoperto `supabase db query --linked`** (Management API): SQL arbitrario senza migration files né psql né DB password. Sblocca i test gap headless dall'host DBA. → D-014 (numerazione locale: vedi DECISIONS, allineare con D-014 EU se collide).
2. **Setup staging in `agents_staging`**: 10 ruoli `t01..t10` LOGIN NOINHERIT NOBYPASSRLS, tabella `canary(owner,payload)` con RLS `USING (owner = session_user)` + FORCE RLS, seed 1 riga/ruolo. Eseguito via `supabase db query --linked -f`. Passwords generate con `secrets.token_urlsafe`, salvate in `.scratch/gap_tests/passwords.json` (gitignored), mai loggate.
3. **Gap A — Supavisor session-mode 10 worker concorrenti: ✅ PASS pieno.**
   - Pooler: `aws-1-eu-west-3.pooler.supabase.com:5432`, user format `<role>.fvoxccwfysazwpchudwp`.
   - Script `gap_a.py` (psycopg2-binary 2.9.11): 10 thread, 10 qps/worker, 300s, query `SELECT current_user, session_user, * FROM agents_staging.canary`.
   - **29.499 query totali, 0 leak, 0 identity violation**. Ogni worker ha visto SOLO la propria riga; `session_user` e `current_user` sempre = login. Hardening 4.1 (session mode) + 4.2 (RLS su session_user) validati empiricamente.
4. **Gap B — REVOKE su `pg_stat_activity`: ❌ FAIL come scritto in hardening 4.5.**
   - `REVOKE SELECT ON pg_catalog.pg_stat_activity FROM t01` → CLI rc=0, ma t01 continua a leggere. Causa: PUBLIC ha SELECT.
   - `REVOKE ... FROM PUBLIC` → CLI rc=0, ma `relacl` invariato: `{supabase_admin=arwdDxtm/supabase_admin,=r/supabase_admin}`. **Causa root: il GRANT a PUBLIC è di proprietà di `supabase_admin`; PostgreSQL impone che solo il grantor (o un membro della sua role) possa revocare. L'utente `postgres` esposto da Supabase managed NON è membro di `supabase_admin` → la REVOKE è no-op silente (rc=0, ACL invariata).**
   - **Hardening 4.5 non implementabile** sul piano gestito Supabase con i privilegi disponibili al DBA del progetto.
   - **Mitigazioni residue empiricamente verificate:**
     - Filtro nativo Postgres su `pg_stat_activity`: t01 vede `query='<insufficient privilege>'` per le connessioni di altri user (campione: 13 hidden / 1 visible su 14 righe).
     - `pg_stat_statements`: non raggiungibile da t01 (`relation does not exist` — extension schema fuori dal search_path) → denied di fatto.
     - **Leak residuo**: `usename`, `datname`, `application_name`, `client_addr`, `state`, `wait_event` di altre connessioni attive → consente *enumerazione dei ruoli attivi* e metadati di sessione.
5. **Cleanup completo**: `agents_staging` schema, `canary` table, ruoli `t01..t10` rimossi (verificato post-cleanup: `SELECT FROM pg_roles WHERE rolname LIKE 't0%' OR rolname='t10'` → 0 righe; `pg_namespace` per `agents_staging` → 0 righe). Nessuna modifica permanente al DB.

### Decisioni
- **D-014 locale** — `supabase db query --linked` come canale operativo headless DBA (allineare numerazione con D-014 EU di S008 prima del commit; probabile rinomina in D-015).
- **D-015 locale** — Hardening 4.5 (REVOKE pg_stat_*) non implementabile su Supabase managed; il piano RLS Phase 1 va emendato (probabile rinomina in D-016).

### Per Loomy — decisione richiesta su Gap B
Tre opzioni di mitigazione, da scegliere prima di scrivere la migration `agents`:
- **B-opt-1**: ticket Supabase support per REVOKE a livello supabase_admin. Esito incerto, plan Free probabilmente rifiuta.
- **B-opt-2** *(preferito DBA)*: accettare il residuo (query text già protetto), neutralizzare l'enumerazione con nomi-ruolo opachi (es. `agt_a8f3kx_doc` invece di `doc_researcher`), demandare forensics a pgaudit + log shipping S3. Cost/benefit migliore, nessuna dipendenza esterna.
- **B-opt-3**: rimuovere 4.5 dalla lista dei 6 hardening obbligatori, amendment esplicito a D-019.

### Stato gap dopo S008+S009
| Gap | Esito | Note |
|---|---|---|
| A — Supavisor session-mode anti-leak | ✅ PASS (29.499 q) | Hardening 4.1 + 4.2 validati |
| B — REVOKE pg_stat_* | ❌ FAIL come scritto | Mitigazione residua parziale; serve scelta opzione |
| C — Docker base | ⏸ S008: Docker non installato sull'host | Bitwarden ora sbloccato (S008), manca solo Docker |

### Artefatti (non committati, gitignored)
- `.scratch/gap_tests/setup.sql`, `teardown.sql`
- `.scratch/gap_tests/gap_a.py`, `gap_b.py`
- `.scratch/gap_tests/passwords.json`

---

## S008 — 2026-04-06 — Bitwarden EU sbloccato, test secret OK, Gap C bloccato (no Docker)

**Partecipanti:** Achille (via task) + DBA (002)

### Cosa è stato fatto
1. **Root cause D-013 identificata e risolta:** il server `bw` era configurato su `vault.bitwarden.com` (US), ma Achille ha account region EU (`vault.bitwarden.eu`). Le credenziali in `env.local.txt` erano sempre state valide — l'utente semplicemente non esiste sul cluster US. `bw config server https://vault.bitwarden.eu` + `bw login --apikey` → **You are logged in!** al primo tentativo, zero rigenerazione chiavi necessaria.
2. **`bw unlock` con `BW_PASSWORD` env** → session token 88 char, sync OK.
3. **Org `LoomX Consulting` (id `1b4d2ef9-2ab0-47e2-88b5-b4240150586f`) + collection `Agents` (id `46b6e1a2-e546-458c-8a7d-b4240150587f`)** confermate via `bw list org-collections`. Nota: nome reale org è "LoomX Consulting" (non "LoomX") e collection è "Agents" (capitale).
4. **Test secret creato:** secure note `rls-poc-test-secret-S008` (id `ca1819c7-9c9b-4f07-959c-b4240160ab23`) nella collection Agents dell'org. Read-back via `bw get item` → OK. Validazione write+read end-to-end del vault EU: PASS.
5. **D-014 scritta** (Bitwarden vault region EU come governance permanente). D-013 marcata come superseded dal contesto di D-014.
6. **CLAUDE.md aggiornato** con sezione "Bitwarden (vault EU)" sotto Regole operative.

### Blocker
- **Gap C BLOCCATO: Docker non installato sull'host DBA.** `docker --version` → command not found; nessuna installazione di Docker Desktop trovata in `C:\Program Files\Docker`. Installare Docker Desktop richiede privilegi admin + decisione di Achille (~500 MB, account Docker, riavvio possibile, abilitazione WSL2 backend). Non procedo autonomamente.
- **Gap A + Gap B non eseguiti in questa sessione** per non interferire con la sessione parallela `bs81dr4fa` lanciata pochi minuti prima del task. Verificato a inizio sessione: `docs/HISTORY.md` e `docs/RLS_PHASE1_PLAN.md` non risultavano aggiornati dalla sessione parallela al momento del check, ma per coerenza con l'istruzione del task ("non interferire se ancora running") non ho avviato Gap A/B in parallelo. Da sincronizzare con la sessione parallela quando entrambe chiudono.
- **Migration `agents` schema + ruolo `doc_researcher` NON scritta** — gate non passato (Gap C bloccato, Gap A/B non confermati passati).

### Decisioni
- D-014 (Bitwarden vault region = EU)

### Stato consegnabili task
| Step | Stato |
|---|---|
| Sblocco Bitwarden EU | ✅ PASS |
| Test secret rls-poc-test-secret-S008 | ✅ PASS |
| Gap A (Supavisor 10 ruoli) | ⏸ deferred a/da sessione parallela |
| Gap B (REVOKE pg_stat_activity) | ⏸ deferred a/da sessione parallela |
| Gap C (Docker base + bw injection) | ❌ BLOCKER — Docker non installato sull'host |
| Migration agents schema (draft) | ⏸ non scritta — gate non passato |

---

## S007 — 2026-04-06 — Sblocco S006 parziale: CLI installati, migration initiative, Bitwarden BLOCKER

**Partecipanti:** Achille (via task) + DBA (002)

### Cosa è stato fatto
1. **Supabase CLI 2.84.2 installato** (binario GitHub release in `~/bin/supabase.exe`) — D-012. Tentativi npm e winget falliti.
2. **Bitwarden CLI 2026.3.0 installato** via `npm install -g @bitwarden/cli`.
3. **Migration `20260406030000_loomx_initiative_rls_security.sql` applicata** via `supabase db push --linked` su `fvoxccwfysazwpchudwp`. project_id `rls-security` = `929ba96c-1450-452d-9ef8-9d059b4c7090`. 6 GTD item legati a initiative.
4. **`env.local.txt` letto** (CRLF strippati, leading-space strippati, lunghezze id=41 secret=30 coerenti). Credenziali NON loggate.

### Blocker
- **Bitwarden API key rifiutata** da `bw login --apikey` (`client_id or client_secret is incorrect`) — D-013. Achille deve rigenerare la API key personale da vault.bitwarden.com (Account Settings → Security → Keys) e aggiornare `env.local.txt`.
- Senza Bitwarden funzionante: step 4 (test secret), Gap C (Docker base con bw injection), step 7 (migration agents) restano bloccati.
- Per istruzione esplicita del task ("se anche un solo gap fallisce: STOP, niente migration agents") non ho proseguito con Gap A/B in cascata, ma sono potenzialmente eseguibili indipendentemente da Bitwarden — attendo decisione di Loomy se proseguire parzialmente.

### Decisioni
- D-012 (Supabase CLI come binario locale)
- D-013 (Bitwarden API key blocker)

---

## S001 — 2026-03-30 — Setup iniziale completo

**Durata:** sessione singola
**Partecipanti:** Achille + DBA (002)

### Cosa è stato fatto

1. **Progetto Supabase creato** — `fvoxccwfysazwpchudwp`, EU West Paris
2. **Namespace `board_*`** — migrazione `20260330100000`
   - `board_agents`: registry agenti con codice numerico progressivo (001-004)
   - `board_messages`: messaggi inter-agente con FK, indici, trigger, RLS deny-all
   - Seed 4 agenti iniziali (PM, DBA, APP, Assistant/Evaristo)
3. **Namespace `home_*`** — migrazione `20260330110000`
   - 10 tabelle app famiglia con prefisso fisico `home_`
   - RLS family-based via `home_get_my_family_id()`
   - Seed function per categorie spesa
4. **Governance**
   - CLAUDE.md: identità agente 002, tabella coordinamento, procedura registrazione
   - Decisioni D-001 → D-005
   - Requisiti REQ-001 → REQ-012 (board_messages)
   - AGENT_REGISTRATION.md: procedura step-by-step
   - SCHEMA.md: documentazione completa entrambi i namespace
5. **Board message inviato** a 003/app: task aggiornamento query con nomi prefissati

### Decisioni prese

| ID | Decisione |
|---|---|
| D-001 | Agent registry con codice numerico progressivo |
| D-002 | Nickname defaults to label via trigger |
| D-003 | RLS deny-all per tabelle board_* |
| D-004 | Progetto Supabase unico per LoomX Home |
| D-005 | Prefisso fisico `home_` su tutte le tabelle app |

### Backlog per prossima sessione

- ~~Attendere risposta da 003/app sul task di aggiornamento query~~ → completato in S002

---

## S002 — 2026-03-30/31 — Board evoluto, school menus, gestione posta

**Durata:** sessione singola (a cavallo di due giorni)
**Partecipanti:** Achille + DBA (002)

### Cosa è stato fatto

1. **Registrazione agente 005/board-mcp (Postman)** — migrazione `20260330120000`
2. **View `board_overview`** — migrazione `20260330130000`, per monitoraggio PM globale
3. **Function `board_broadcast`** — migrazione `20260330140000`, invio a tutti gli agenti attivi
4. **Tabella `home_school_menus`** — migrazione `20260331100000` (richiesta 003/app)
   - Menù scolastico per bambino, source manual/scraper, UNIQUE per giorno
5. **Evoluzione `board_messages`** — migrazione `20260331110000` (richiesta 005/Postman)
   - `tags TEXT[]` con indice GIN
   - `summary TEXT` per lettura token-efficient
   - `archived_at TIMESTAMPTZ` con function `board_archive_old()`
   - View `board_overview` aggiornata
6. **Gestione posta board** — processati messaggi da PM, App, Postman
   - Relay messaggio PM → Postman (tool implementation + roadmap D-008)
   - Aggiornato nickname 005 a "Postman"
   - Notificato governance onboarding al PM

### Decisioni prese

| ID | Decisione |
|---|---|
| D-006 | board_messages: tags, summary, archived_at |

### Backlog per prossima sessione

- Inbox vuota, nessun task pendente

---

## S003 — 2026-04-05 — Allineamento governance

**Durata:** micro-sessione
**Partecipanti:** Achille + DBA (002)

### Cosa è stato fatto

1. **Aggiornamento governance** — direttiva da Loomy (001, root coordinator)
   - Il PM Home non esiste più; il coordinatore è ora Loomy
   - I TODO.md sono deprecati: i task si gestiscono via tool GTD del Board MCP (`gtd_inbox`, `gtd_add`, `gtd_update`, `gtd_complete`) su tabella `loomx_items`
   - Tutti i task DBA erano già completati, niente da migrare
2. **docs/TODO.md** — aggiunto avviso di deprecazione in cima al file
3. **CLAUDE.md** — già aggiornato nella sessione precedente (nessuna modifica necessaria)

### Decisioni prese

| ID | Decisione |
|---|---|
| D-007 | TODO.md deprecato, task gestiti via GTD Board MCP (loomx_items) |

### Backlog per prossima sessione

- Nessun task pendente

---

## S004 — 2026-04-06 — Garmin sync user e RLS policies

**Durata:** micro-sessione
**Partecipanti:** Achille + DBA (002)

### Cosa è stato fatto

1. **Migrazione `20260406020000_home_garmin_health_rls_sync_user.sql`** — RLS policies per utente dedicato garmin-sync
   - SELECT/INSERT/UPDATE su `home_garmin_health` per email `garmin-sync@loomx.local`
   - No DELETE, no accesso ad altre tabelle (deny-all pattern)
   - Utente auth creato via Admin API (non in SQL migration per compatibilità schema auth)
2. **Decisione D-009** — utente auth dedicato anziché service_role per script esterni

### Decisioni prese

| ID | Decisione |
|---|---|
| D-009 | Utente auth dedicato per garmin_fetch.py (no service_role) |

### Backlog per prossima sessione

- Applicare migrazione `20260406010000` (tabella) e `20260406020000` (policies) su Supabase
- Creare utente auth via Admin API

---

## S005 — 2026-04-06 — Analisi sicurezza strategia RLS/auth agenti

**Durata:** analisi (no code)
**Partecipanti:** Achille + DBA (002)

### Cosa è stato fatto

1. Analisi comparativa di 4 approcci (auth user JWT, DB role puro, doppio livello, defense in depth) su 9 criteri di sicurezza.
2. Raccomandazione finale: **Approccio D — Defense in depth** con DB role per-agente come primitiva primaria, RLS su `current_user`, connessione via Supavisor (no PostgREST per MCP bot), 1Password CLI per secret, audit trail via pgaudit/trigger, rotazione automatica, network restrictions.
3. Documento salvato in `docs/RLS_SECURITY_ANALYSIS.md` con matrice di confronto, piano di rollout in 7 fasi, rischi residui.
4. In parallelo Achille chiede analisi indipendente al researcher come challenge.

### Decisioni prese

Nessuna decisione finalizzata — analisi in attesa di challenge researcher e approvazione Achille prima di aprire una nuova D-010.

### Backlog per prossima sessione

- Ricevere analisi researcher e confrontarla con questa.
- Se approvata, aprire GTD items per rollout fase 1 (DB role + GRANT matrix su namespace pilota board_).

---

## S006 — 2026-04-06 — RLS Phase 1 kickoff + initiative pattern

**Durata:** sessione singola
**Partecipanti:** Achille + DBA (002)
**Trigger:** msg `1c917ca8` (GO formale RLS), `0867882a` (Bitwarden pronto), `f68ff802` (initiatives task).

### Cosa è stato fatto

1. **Pre-flight completo:** letti D-018/D-019/D-020 di Loomy, `hub/initiatives/rls-security/design.md`, confermata comprensione dei 6 hardening.
2. **Migration initiative `rls-security`** — `20260406030000_loomx_initiative_rls_security.sql`:
   - INSERT in `loomx_projects` con `short_name='rls-security'`, `type='internal'`, `agent_id='dba'`, sponsor in `notes`
   - INSERT 6 link in `loomx_item_projects` per i GTD item RLS (originale + Fase 1-4)
   - **NON applicata** (no `supabase` CLI sull'host DBA)
3. **Piano operativo RLS Phase 1** in `docs/RLS_PHASE1_PLAN.md`:
   - Tabella di mappatura 6 hardening → istruzioni migration
   - Spec dei 3 gap empirici (A: Supavisor leak, B: REVOKE pg_stat_activity, C: Docker base) con setup, pass criteria, fail mitigation
   - Bozza migration `agents` schema + ruolo `doc_researcher` (solo bozza, non committata)
   - Skeleton Dockerfile + entrypoint Bitwarden + plan `agent_manager.py` Docker-aware
   - Riepilogo blocker

### Decisioni prese

- **D-010** Initiative pattern: riusare `loomx_projects` (no nuova tabella). Divergenza vs richiesta Loomy: solo `agent_id`, non `owner_agent`/`sponsor_agent` separati — sponsor in `notes`.
- **D-011** RLS Phase 1: gate dei 3 gap empirici prima di scrivere la migration `agents`. Nessuna migration scritta finche' i gap non passano.

### Blocker incontrati

1. **No `supabase` CLI** sull'host DBA → impossibile applicare la migration initiative o eseguire i gap test in staging. Achille deve applicare via Studio o installare CLI.
2. **Credenziali Bitwarden vault** non ancora condivise → Gap C (Docker base) bloccato sul passo `bw login`.
3. **D-018 (co-engagement N:N tabella `loomx_item_agents`)** non implementato → la policy RLS draft per `doc_researcher` ha solo `owner = 'researcher' OR waiting_on = 'researcher'`, manca il caso co-engagement esplicito. TODO nel draft migration.

### Prossimi step

- [Achille] applicare migration `20260406030000` o sbloccare CLI sul DBA
- [Achille] passare credenziali Bitwarden iniziali per Gap C (canale fuori board)
- [DBA] eseguire Gap A/B/C non appena sbloccato
- [DBA] dopo gate gap → migration `agents` schema + ruolo `doc_researcher`
- [Loomy] ricevere `project_id` di rls-security una volta applicata la migration (non posso recuperarlo senza CLI)

---

## S014 — 2026-04-07 — Merge feat/direct-postgres-backend (D-023, 7/7 PASS)

**Durata:** sessione singola
**Trigger:** GTD `874ec051` waiting + msg `9d8ca052` review+merge branch Postman.

### Cosa è stato fatto

1. **Sblocco BW** dopo workaround PowerShell: `bw.cmd` (o cmd.exe) bypassa execution policy. Achille passa `BW_SESSION` token, recupero pwd `doc_researcher` dal vault EU `loomx/agents/doc_researcher`.
2. **2 fix DB scoperti durante i test**:
   - Migration `20260407150000_doc_researcher_read_grants.sql`: GRANT SELECT + policy SELECT su `board_agents` (server MCP non parte senza, `resolveAgentRegistry` fallisce); GRANT SELECT + policy SELECT su `board_messages` (`USING (session_user='doc_researcher' AND (to_agent='021' OR from_agent='021'))`).
   - Senza questi grant la migration `20260407100000` è incompleta: copre solo INSERT su board_messages e GTD su loomx_items, non il path "leggi i tuoi messaggi".
3. **7-step spec D-023 §4** eseguito via test driver (mock McpServer cattura handlers) contro EU pooler con pg-shim → **7/7 PASS reali**:
   - T1 `current_user=session_user=doc_researcher` ✓
   - T2 `board_inbox` researcher legge solo i propri ✓
   - T3 `gtd_add` owner=researcher ✓
   - T4 `gtd_add` owner=dba DENY (tool layer enforcement)
   - T5 `board_send` researcher→dba ✓
   - T6 spoof `from_agent='002'` via INSERT diretto → RLS WITH CHECK violato ✓
   - T7 (bonus) spoof `loomx_items` owner='dba' via INSERT diretto → RLS WITH CHECK violato ✓
4. **Cleanup test rows**: 3 GTD (`05e92924`, `94d73407`, `139e8b41`) + 1 board msg (`62409727`) eliminati.
5. **Merge**: in repo `loomx-board-mcp` committato branch `feat/direct-postgres-backend` come `0ef50eb` (include `src/pg-shim.ts` untracked + 10 file modificati di Postman + fix DBA S013), poi merge no-ff in master come `0f93bee`. Master locale 6 commit ahead di origin.

### Decisioni prese

Nessuna nuova decisione formale.

### Bug catch (caveat per Phase 2)

- T4 in realtà NON prova RLS DB-side: blocco viene dal tool layer (`only loomy can create items for other agents`). T7 (aggiunto) copre il caso DB-side bypassando il tool. Per Phase 2 ricordarsi di testare entrambi i path per ogni agente.
- Test driver iniziale aveva false-positive su "permission denied → PASS"; rifatto con `isError()` strict.

### Blocker aperti

1. **Push remoto loomx-board-mcp/master** in attesa di OK esplicito Achille (sessione ha autorizzato il merge, non il push).
2. **Msg `e90274f7`** (RPC sprint 005 home_school_menu_sync da App): pending, non toccato.

### Prossimi step

- [Achille] OK push origin master loomx-board-mcp → DBA pusha + summary `done` a Loomy con `0f93bee`
- [Loomy] aggiornamento `hub/researcher/.mcp.json` con `DATABASE_URL=doc_researcher@...` → POC settimana parte
- [DBA] task RPC `home_school_menu_sync` per App (sprint 005)
- [DBA, Phase 2] estendere read grants pattern (board_agents + board_messages SELECT) ai 9 ruoli rimanenti

### Estensione S014 (sera) — RPC sprint 005 + utenza assistant

1. **Inbox triage**: 4 messaggi stantii chiusi (done/cancelled), 2 archiviati subito.
2. **Risposta Evaristo (assistant) + question Loomy `.mcp.json` gap**: entrambe inviate. La question di Loomy era già risolta dal merge serale di pg-shim.
3. **Migration `20260408010000_home_school_menu_sync_rpc.sql`**: 2 funzioni `SECURITY DEFINER` per sprint 005 di App:
   - `home_school_menu_sync(family, member, week_start, dishes jsonb) → jsonb` — atomic upsert in home_school_menus + mirror in home_menu_items + skip esclusioni. Convenzione `day_of_week` 1..7 ISO.
   - `home_school_menu_toggle_exclusion(family, member, date, reason, excluded) → jsonb` — toggle atomico esclusione + cleanup/restore mirror row.
   - Auth: `home_get_my_family_id() = p_family_id` OR `auth.jwt() ->> 'email' = 'scraper@loomx.local'`.
   - Hardening: `SET search_path = public, pg_temp` su entrambe.
   - Applicata via `supabase db query --linked --file`, verificata `EXECUTE` su `authenticated`.
4. **Utenza assistant per Evaristo** (su richiesta diretta Achille "creale tu, sei DBA"):
   - Verificato che `scraper@loomx.local` esisteva già (creato dal `setup-scraper.mjs` di App), lasciato intatto.
   - Creato `assistant@loomx.local` via INSERT diretto in `auth.users` (clonando struttura scraper) + bcrypt pwd via `crypt(pwd, gen_salt('bf'))`.
   - Registrato in `home_profiles` come membro della famiglia Barban (display_name='Evaristo (assistant)', role='member').
   - Pwd random 32-char generata via openssl, salvata nel vault Bitwarden EU come Secure Note `loomx/auth/assistant` (convenzione D-014: ultima riga del campo notes), con field email + user_id.
   - Smoke test: vault pwd ↔ `encrypted_password` match via crypt → PASS.
   - Cleanup file temp.
   - Notifica Evaristo con istruzioni signInWithPassword + scope home_* via RLS family-based, niente service_role.
   - Errata corrige inviata ad App: il bloccante umano "Achille deve creare scraper" che avevo segnalato non esiste.

### Decisioni operative aggiuntive

- **D-022 (locale, da formalizzare)**: pattern "agente Supabase Auth dedicato + home_profiles membership" come stop-gap pre-Phase 2 per agenti che operano solo su `home_*`. Più semplice del ruolo Postgres nativo (non richiede pg-shim/DATABASE_URL), riusa RLS esistente. Da promuovere in DECISIONS.md prossima sessione.

### Stato finale inbox dopo S014

- Tutti i messaggi pending gestiti (risposte + ack)
- Solo i 2 stantii più recenti restano "in attesa di archive_old days≥2"
- Nessun bloccante umano residuo per nessun agente


---

## S015 — 2026-04-09 — Inbox triage sprint 005/007

### Cosa è stato fatto

1. **Blocker App day_of_week** (msg `a1ee8bdf`): migration `20260408020000_home_day_of_week_iso.sql` (creata in coda S014, non ancora committata) verificata applicata al DB — `home_school_menus` e `home_menu_items` ora con CHECK BETWEEN 1 AND 7 (ISO). Risposta done ad App con heads-up frontend (`Date.getDay()` da normalizzare).
2. **Task App guest_names** (msg `9572f254`): migration `20260408030000_home_menu_items_guest_names.sql` creata e applicata. `home_menu_items.guest_names text[] NOT NULL DEFAULT '{}'`. Verificato che NON esiste UNIQUE su `(menu_id, day_of_week, meal_type)` → multi-row per cella già ammesso, sprint 007 non richiede altre modifiche schema. Risposta done.
3. **RPC home_school_menu_sync** (msg `e90274f7`): già implementata in S014, status aggiornato a `done`.

### Stato inbox

Tutti i pending azionabili chiusi. Restano 9 acknowledged storici (RLS Phase 1, D-018, governance tag) che sono GTD-tracked, non richiedono azione.

### Migration committate in S015

- `20260407150000_doc_researcher_read_grants.sql` (S013, era untracked)
- `20260408010000_home_school_menu_sync_rpc.sql` (S014)
- `20260408020000_home_day_of_week_iso.sql` (S014, hotfix sprint 005)
- `20260408030000_home_menu_items_guest_names.sql` (S015, sprint 007)
