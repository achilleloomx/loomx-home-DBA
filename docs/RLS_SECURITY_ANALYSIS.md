# Analisi sicurezza: strategia autenticazione e autorizzazione agenti LoomX

**Data:** 2026-04-06
**Autore:** DBA (002)
**Contesto:** Follow-up piano RLS sessione precedente (D-016/GTD `e402d9d1`). Achille chiede approccio che **massimizza la sicurezza**, anche a costo di effort e complessità.
**Non implementativo.** Solo analisi comparativa.

---

## 1. Situazione attuale (baseline insicura)

- Ogni agente ha `SUPABASE_SERVICE_ROLE_KEY` nel proprio `.mcp.json`.
- `service_role` bypassa RLS → accesso totale a tutto lo schema (board_, home_, loomx_).
- Un solo `.mcp.json` esfiltrato = compromissione totale del progetto Supabase.
- Zero audit trail per agente: i log Postgres vedono solo il ruolo `service_role`.
- Rotazione: unica chiave condivisa → rotazione = downtime coordinato su tutti i repo.

Pattern consolidato (D-003, D-008, D-009): RLS deny-all + accessi espliciti. D-009 ha già provato su piccola scala il pattern "auth user dedicato" (garmin-sync).

---

## 2. Approcci candidati

### A. Solo auth user (JWT Supabase GoTrue) — l'approccio C della sessione precedente
Ogni agente ha un utente `auth.users` (`slug@loomx.local`) + password. Il client MCP chiama `signInWithPassword` e usa l'access token JWT per ogni query via PostgREST. RLS policies filtrano su `auth.jwt() ->> 'email'` o `auth.uid()`.

### B. Solo DB role Postgres nativo
Ogni agente ha un ruolo Postgres (`CREATE ROLE agent_app LOGIN PASSWORD ...`), **non** un auth user. Accesso diretto via Supavisor/PgBouncer (port 6543/5432), non via PostgREST. GRANT granulare a livello tabella/colonna. RLS opzionale (usiamo direttamente i GRANT + `SET ROLE`).

### C. Doppio livello: DB role (connessione) + auth user (identità applicativa)
Il client si connette via DB role condiviso `agent_runner` (con GRANT minimi comuni), poi assume l'identità dell'agente via `SET LOCAL role` o via JWT applicativo custom letto in RLS. Variante: DB role per-agente + JWT per-request per audit fine.

### D. Defense in depth completo (raccomandato)
Combinazione di A + B + controlli aggiuntivi:
- **DB role per-agente** con `LOGIN` e GRANT minimi (linea di difesa 1: motore Postgres).
- **RLS policies** su tutte le tabelle, scritte contro `current_user` (il DB role) **e** `auth.jwt()` dove serve audit su richiesta umana (linea 2).
- **Secret storage centralizzato** (non `.env` chiari).
- **Network policy**: Supabase "Network Restrictions" / allowlist IP se possibile, o almeno connessione solo via Supavisor con TLS obbligatorio.
- **Audit trail** via trigger su tabelle sensibili + `pgaudit` se disponibile, loggando `current_user` + `current_setting('app.agent_slug', true)`.
- **Rotazione automatica** via script DBA + Supabase Vault per le chiavi.

---

## 3. Matrice di confronto

| Criterio | A. Auth user JWT | B. DB role puro | C. Doppio livello | D. Defense in depth |
|---|---|---|---|---|
| **Superficie attacco** | Media — PostgREST esposto pubblico | Bassa — connessione DB diretta, no PostgREST per agenti | Media | **Minima** — agenti via Supavisor + RLS + GRANT |
| **Granularità permessi** | Buona (RLS) | **Ottima** (GRANT tabella/colonna + RLS) | Ottima | **Ottima** |
| **Audit "chi ha fatto cosa"** | Buona (email nel JWT, log PostgREST) | **Ottima** (`current_user` nei log Postgres) | **Ottima** | **Ottima + immutabile** (pgaudit + trigger) |
| **Rotazione credenziali** | **Facile** (Admin API update password) | Media (`ALTER ROLE ... PASSWORD`) | Complessa (2 credenziali) | Media-alta, ma automatizzabile |
| **Blast radius se `.mcp.json` leaked** | Accesso HTTP a PostgREST finché non revochi token/password. Limitato dai ruoli RLS. | Accesso DB diretto ma solo a tabelle con GRANT. Niente accesso ad altri agenti. | Come B per il DB role, più l'identità applicativa è cifrata | **Come B** + network allowlist riduce ulteriormente + audit immediato rileva anomalie |
| **Complessità operativa** | **Bassa** (stack Supabase standard) | Media (gestione ruoli Postgres manuale) | **Alta** | **Alta** |
| **Allineamento con stack esistente** | **Alto** (D-009 già fa così) | Medio | Basso | Medio |
| **Compatibilità MCP server Supabase** | **Alta** (usa supabase-js) | Richiede MCP server postgres generico o client custom | Richiede custom | Mista (alcuni agenti A, altri B) |
| **Difesa contro SQL injection in policy** | Debole se policy usano `jwt() ->> 'claim'` con cast errati | **Forte** (GRANT non si può bypassare) | Forte | **Forte** |
| **Defense in depth** | 1 livello (RLS) | 2 livelli (GRANT + RLS opzionale) | 2-3 livelli | **4+ livelli** (GRANT + RLS + network + audit) |

---

## 4. Analisi per criterio chiave

### 4.1 Minimizzazione superficie d'attacco
PostgREST è un endpoint HTTP pubblico: qualunque chiave/JWT valido raggiunge il server da qualsiasi IP. Un DB role via Supavisor (pooler) accetta invece solo connessioni TLS autenticate e può essere limitato a IP list se Supabase Pro+ è disponibile. **Vincitore: B/D.**

### 4.2 Rotazione credenziali
- **A:** `supabase.auth.admin.updateUserById(id, { password })` + update `.mcp.json` → una chiamata API + file write. Il più semplice.
- **B:** `ALTER ROLE agent_x PASSWORD '...'` → una query SQL + update `.mcp.json`. Semplice ma serve connessione superuser.
- **D:** combina entrambi; script unico che ruota ogni 90 giorni scrive in Supabase Vault e aggiorna i `.mcp.json` via template.
**Vincitore automazione: A. Vincitore con Vault: D.**

### 4.3 Audit trail "quale agente fisico"
- **A:** i log PostgREST registrano email utente → OK, ma dipende da log retention Supabase (non immutabile lato nostro).
- **B:** `log_statement = 'all'` + `log_line_prefix` con `%u` → `current_user` = slug agente, nativamente in Postgres log. Possiamo copiare in tabella `loomx_audit_log` via `pgaudit` o trigger.
- **D:** trigger `BEFORE INSERT/UPDATE/DELETE` su tabelle sensibili scrive riga in `loomx_audit_log` con `current_user`, `current_setting('app.agent_slug', true)`, `now()`, `old/new row`. Tamper-evident se la tabella è append-only via policy.
**Vincitore: D.**

### 4.4 Blast radius se `.mcp.json` esfiltrato
Scenario: attaccante ottiene `.mcp.json` del Researcher.
- **Stato attuale:** pieno controllo DB, può droppare schemi, leggere dati famiglia, cancellare GTD. **Catastrofico.**
- **A (Researcher con auth user + RLS INSERT-only su board_messages):** può solo inserire messaggi, non leggere home_, non leggere altri board_messages. Può però spammare il board e consumare quota. Esposto via HTTPS da qualsiasi IP.
- **B (Researcher con DB role + GRANT INSERT su board_messages):** identico ad A lato permessi, ma richiede connessione al pooler → se c'è allowlist IP, attaccante deve stare su rete autorizzata.
- **D:** come B + audit rileva pattern anomalo + rotazione automatica limita finestra temporale + Supabase Vault rende harvesting dei `.mcp.json` inutile (contengono solo reference, non secret).
**Vincitore: D.**

### 4.5 Defense in depth
Solo **D** offre più di 2 livelli indipendenti. Se un livello cede (es. bug in RLS policy), gli altri (GRANT, network, audit) mantengono il contenimento.

### 4.6 Secret storage
Confronto:

| Soluzione | Sicurezza | Semplicità per Achille (single user) | Integrabile con MCP | Note |
|---|---|---|---|---|
| `.env` in chiaro | Bassa | Massima | Sì | **Stato attuale, da abbandonare.** |
| `.env` + SOPS/age | Media-alta | Media | Sì (decrypt pre-run) | Gratis, git-friendly, chiave locale. Buon compromesso. |
| 1Password CLI (`op run`) | **Alta** | **Alta** (Achille probabilmente già lo usa) | Sì (`op inject` nei `.mcp.json`) | Audit log 1P, rotazione manuale ma tracciata. **Raccomandato pragmatico.** |
| Doppler | Alta | Media (altro SaaS) | Sì | Aggiunge vendor. |
| HashiCorp Vault | **Massima** | Bassa (setup/maintenance pesante) | Sì ma custom | Overkill per single-dev. |
| Supabase Vault (pgsodium) | Alta **per secret consumati dal DB**, non per client esterni | Media | Non per `.mcp.json` | Utile per secret che il DB stesso usa (es. webhook keys), non per credenziali di connessione. |

**Raccomandazione:** 1Password CLI + `op inject` per i `.mcp.json` (generati on-demand e mai committati), Supabase Vault per eventuali secret server-side.

### 4.7 DB role + auth user combinati — fattibile?
Sì, due pattern:

1. **DB role con `rolinherit` di un ruolo base + JWT per audit:** il client usa il DB role per connettersi via pooler; il DB role ha GRANT minimi. All'inizio di ogni transazione il client esegue `SELECT set_config('app.agent_slug', 'researcher', true)` e le RLS/trigger loggano quel valore. Il secret è solo la password DB. **Pro:** un solo secret. **Contro:** `app.agent_slug` è auto-dichiarato, non autenticato → non è vera identità, solo marker audit.
2. **Auth user (JWT firmato) + DB role lato server:** PostgREST map automatica JWT → ruolo. Qui `auth.uid()` è autenticato. **Pro:** identità forte. **Contro:** resta PostgREST-based, non risolve superficie d'attacco di 4.1.

**La combinazione più robusta** (raccomandazione, vedi §5): **DB role per agente** (autenticazione forte a livello connessione) + **variabile di sessione** `app.agent_slug` (solo audit, non security boundary) + **RLS** scritte su `current_user` (non su `app.agent_slug`, per evitare spoofing). L'auth user Supabase rimane solo per agenti che **devono** passare da PostgREST (es. se esiste un'app frontend che usa quella identità — non il nostro caso per gli MCP).

---

## 5. Raccomandazione finale

**Approccio D — Defense in depth, con DB role per-agente come primitiva primaria.**

### Architettura proposta

1. **Un DB role Postgres per agente** (`agent_researcher`, `agent_app`, `agent_assistant`, ...), con `LOGIN`, password random 32+ char, **no** superuser, **no** createrole.
2. **GRANT chirurgici** per ogni ruolo sulle sole tabelle necessarie, con colonne esplicite dove utile. Nessun `GRANT ALL`. Default `REVOKE ALL` sullo schema public per i nuovi ruoli.
3. **RLS abilitato ovunque** (già D-003/D-008). Policy scritte contro `current_user` (es. `USING (current_user = 'agent_researcher' AND ...)`) — non contro variabili di sessione spoofabili. Policy aggiuntive per filtrare righe (es. Researcher vede solo i propri `board_messages`).
4. **Connessione via Supavisor** (transaction mode, port 6543) da tutti gli agenti MCP. Niente PostgREST per i bot. PostgREST resta per l'app Home utente-finale (home app con auth user).
5. **Service role key revocata dai `.mcp.json`** di tutti tranne DBA. Il DBA la conserva in 1Password (non nel `.mcp.json`), la inietta solo quando serve per operazioni di schema.
6. **Network restrictions** attive su Supabase (se piano lo permette) con allowlist IP workstation Achille + eventuali runner CI. Se non disponibile, almeno `sslmode=require` obbligatorio e monitoring log per geo-anomalie.
7. **Audit trail** con:
   - `pgaudit` se disponibile su Supabase (verificare), altrimenti
   - Trigger generico `log_changes()` su tabelle sensibili (home_*, loomx_clients, loomx_items) che scrive su `loomx_audit_log` (append-only via policy + `REVOKE UPDATE,DELETE`).
   - Colonne: `ts`, `db_user` (`current_user`), `action`, `table_name`, `pk`, `diff jsonb`.
8. **Secret storage:** 1Password CLI con vault dedicato "LoomX Agents". I `.mcp.json` sono template `.mcp.json.tpl` committati con riferimenti `op://LoomX Agents/researcher/password`, risolti con `op inject -i .mcp.json.tpl -o .mcp.json` a cold-start. Il file risolto è in `.gitignore`.
9. **Rotazione automatica:** script `rotate_agent_creds.sh` eseguito dal DBA (manuale o cron): genera nuova password, `ALTER ROLE ... PASSWORD`, aggiorna 1Password, rigenera `.mcp.json` via `op inject`. Rotazione iniziale 90 giorni; accelerabile a on-demand se incidente.
10. **DBA mantiene** service_role key + ruolo `postgres` superuser, entrambi **solo in 1Password**, mai nel `.mcp.json` di default. Per operazioni privilegiate: `op run -- claude ...` con env var iniettata solo nella sessione.

### Per agenti che **devono** parlare a PostgREST (es. futura Home app utente)
Usano auth user Supabase standard (pattern D-009), con RLS policies scritte su `auth.jwt() ->> 'email'` o meglio su un ruolo custom. Questo è un caso diverso (utente umano), non agent-to-agent.

### Per MCP server Supabase ufficiali che richiedono service_role
Se un MCP server richiede obbligatoriamente service_role, **non lo usiamo** per gli agenti ristretti. Valutiamo MCP postgres generico che accetta DSN con DB role. Alternativa: fork/wrapper MCP che inietta un JWT derivato dal DB role.

---

## 6. Impatto su effort e complessità

| Voce | Effort | Note |
|---|---|---|
| Creazione DB role per 11 agenti + GRANT | Medio (1 migrazione + matrice) | Scriptabile |
| Riscrittura policy RLS contro `current_user` | Medio-alto | Tabelle home_ già hanno helper `home_get_my_family_id()` riutilizzabile |
| Setup 1Password Vault + template `.mcp.json.tpl` | Basso-medio | Una tantum per agente |
| Cambio client MCP da supabase-js a pg diretto dove serve | Medio | Impatta repository degli agenti, serve PR su ognuno |
| `pgaudit`/trigger log | Medio | Verificare disponibilità su Supabase managed |
| Network restrictions | Basso | Config Supabase dashboard, se piano lo permette |
| Script rotazione | Basso | Bash + `supabase` CLI + `op` |
| Test smoke per agente | Medio | Uno per agente, verifica accesso tabelle attese e deny sugli altri |
| **Totale** | **Alto ma contenuto**, ~2-3 sprint DBA + coordinamento con PO di ogni agente | Scalabile per fasi |

**Piano di rollout suggerito (per fasi, ogni fase = stato sicuro):**
1. Fase 1: creare DB role + GRANT + RLS, ma lasciare service_role attivo nei `.mcp.json` (dual-run).
2. Fase 2: migrare un agente pilota (Researcher — lowest blast radius) ai nuovi creds, validare.
3. Fase 3: migrare gli altri agenti uno alla volta, dal meno al più critico.
4. Fase 4: 1Password + template `.mcp.json.tpl`.
5. Fase 5: audit trail + trigger.
6. Fase 6: revoca service_role da tutti tranne DBA. Rotazione #1.
7. Fase 7: network restrictions (se disponibile).

---

## 7. Rischi residui anche con l'approccio scelto

1. **Compromissione della workstation di Achille** → 1Password unlocked + sessione MCP attiva = attaccante eredita tutti i ruoli agent contemporaneamente. Mitigazione: 1P auto-lock breve, full-disk encryption, no agent forwarding.
2. **Bug nelle policy RLS** → un errore di logica può permettere letture cross-agente. Mitigazione: test RLS automatici (pgTAP o plpgsql asserts) eseguiti nel CI DBA. Serve sprint dedicato.
3. **Pgaudit non disponibile su Supabase** → fallback a trigger è più fragile (overhead + bypass via `session_replication_role`). Mitigazione: verificare con Supabase support; se no, trigger + revoca `session_replication_role` ai ruoli agent.
4. **Superuser DB ancora esistente** (DBA) → compromissione sessione DBA = game over. Mitigazione: DBA usa service_role/superuser solo on-demand, non di default.
5. **Supabase control plane** (dashboard API key) non è coperto da questa analisi. Se esfiltrato, un attaccante può leggere/ruotare qualsiasi credenziale a livello progetto. Mitigazione: MFA obbligatoria, API key personali scoped.
6. **Dependency chain degli MCP server** — un update maligno di un pacchetto npm/py usato dagli agenti può esfiltrare i secret al runtime. Mitigazione: lockfile + review update + 1P iniezione solo-runtime riduce finestra.
7. **Rotazione automatica fallita silenziosa** → password scadute non ruotate = allarme. Mitigazione: monitoring scadenza nel GTD del DBA.
8. **Variabile di sessione `app.agent_slug` è auto-dichiarata** — l'abbiamo esclusa come security boundary per questo motivo; resta solo audit best-effort. L'identità forte rimane `current_user`.

---

## 8. Confronto sintetico (TL;DR)

- **Approccio A (auth user)** — il più semplice, stack-nativo, ma 1 solo livello di difesa e PostgREST pubblico. **Sufficiente per singoli casi** (garmin-sync D-009), non ottimale come strategia globale.
- **Approccio B (DB role puro)** — forte, minor superficie, audit nativo, ma complica l'integrazione con MCP supabase-js. Buon core, da completare.
- **Approccio C (doppio livello auth+app)** — aggiunge complessità senza dare identità forte a meno di non usare JWT autenticato, nel qual caso ricade in A.
- **Approccio D (defense in depth = DB role + RLS + 1Password + network + audit + rotation)** — **scelto**. Alto effort ma allineato all'obiettivo "massima sicurezza anche a costo di complessità".

---

## 9. Prossimi passi (se Achille approva)

1. Attendere analisi indipendente del researcher (challenge).
2. Confronto tra le due analisi → raccolta discrepanze → risoluzione con Achille.
3. Aprire GTD items in fasi per il rollout (§6).
4. Scrivere prima migrazione: creazione ruoli + matrice GRANT + RLS riscritte, su un namespace pilota (probabilmente `board_`).
5. Registrare decisione D-010 (o successiva) con la strategia approvata.

**Watermark analisi:** 2026-04-06 — DBA 002.
