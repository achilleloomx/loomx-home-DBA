# Requisiti — Board Messages

> Requisiti atomici estratti da `REQUEST_board_messages.md` (MCP Agent, 2026-03-30)
> e integrati con decisioni architetturali concordate con Achille.

---

## Agent Registry

### REQ-001 — Tabella board_agents come registry centralizzato degli agenti

---
id: REQ-001
headline: "Tabella board_agents come registry centralizzato degli agenti"
type: funzionale
priority: must
stream: "[CORE]"
source: conversation:2026-03-30
depends:
status: proposed
status_date: 2026-03-30
---

Il sistema deve avere una tabella `board_agents` che funge da rubrica di tutti gli agenti
registrati nel Board. Ogni agente è identificato da un codice numerico progressivo a 3 cifre
(`001`, `002`, ...) come chiave primaria di tipo `TEXT`.

**Accettazione:** La tabella `board_agents` esiste con PK `agent_code TEXT`.

---

### REQ-002 — Ogni agente ha slug, label, nickname e scope

---
id: REQ-002
headline: "Ogni agente ha slug, label, nickname e scope"
type: funzionale
priority: must
stream: "[CORE]"
source: conversation:2026-03-30
depends: REQ-001
status: proposed
status_date: 2026-03-30
---

Ogni record in `board_agents` contiene:
- `agent_code` (PK) — codice numerico progressivo 3 cifre
- `slug` (UNIQUE, NOT NULL) — identificativo breve URL-safe
- `label` (NOT NULL) — nome esteso leggibile
- `nickname` — nome amichevole; se NULL, il sistema usa `label`
- `scope` (NOT NULL) — descrizione delle responsabilità
- `repo` — nome del repository associato
- `active` — flag attivo/disattivo, default `true`
- `created_at` — timestamp creazione

**Accettazione:** Tutti i campi sono presenti con i vincoli specificati. `slug` ha constraint UNIQUE.

---

### REQ-003 — Nickname defaults to label quando non specificato

---
id: REQ-003
headline: "Nickname defaults to label quando non specificato"
type: business-rule
priority: must
stream: "[CORE]"
source: conversation:2026-03-30
depends: REQ-002
status: proposed
status_date: 2026-03-30
---

Se `nickname` è NULL, il sistema deve trattarlo come se fosse uguale a `label`.
Implementazione via trigger BEFORE INSERT/UPDATE che copia `label` in `nickname` quando NULL.

**Accettazione:** `INSERT INTO board_agents (agent_code, slug, label, scope) VALUES ('999', 'test', 'Test Agent', 'Test')` → `nickname = 'Test Agent'`.

---

### REQ-004 — Seed dei 4 agenti iniziali

---
id: REQ-004
headline: "Seed dei 4 agenti iniziali"
type: funzionale
priority: must
stream: "[CORE]"
source: conversation:2026-03-30
depends: REQ-001, REQ-002
status: proposed
status_date: 2026-03-30
---

La migrazione include l'inserimento dei 4 agenti fondatori:

| Code | Slug | Label | Nickname | Scope | Repo |
|---|---|---|---|---|---|
| `001` | `pm-home` | Project Manager — LoomX Home | *(null→label)* | Coordinamento progetto LoomX Home | `loomx-home-pm` |
| `002` | `dba` | Database Administrator — LoomX Home | *(null→label)* | Schema Supabase, migrazioni, RLS, permessi | `loomx-home-DBA` |
| `003` | `app` | Product Owner — LoomX Home | *(null→label)* | Sviluppo PWA famiglia | `loomx-home-app` |
| `004` | `assistant` | Home Assistant — LoomX Home | Evaristo | Assistente domestico famiglia | `loomx-home-assistant` |

**Accettazione:** Dopo la migrazione, `SELECT count(*) FROM board_agents` = 4.

---

## Board Messages

### REQ-005 — Tabella board_messages per comunicazione inter-agente

---
id: REQ-005
headline: "Tabella board_messages per comunicazione inter-agente"
type: funzionale
priority: must
stream: "[CORE]"
source: document:REQUEST_board_messages.md
depends: REQ-001
status: proposed
status_date: 2026-03-30
---

Il sistema deve avere una tabella `board_messages` per lo scambio di messaggi tra agenti.
Campi: `id` (UUID PK), `from_agent` (FK → board_agents), `to_agent` (FK → board_agents),
`type`, `subject`, `body`, `ref_id` (self-referencing FK), `status`, `created_at`, `updated_at`.

**Accettazione:** La tabella esiste con tutte le colonne e le FK verso `board_agents`.

---

### REQ-006 — from_agent e to_agent devono essere agenti diversi

---
id: REQ-006
headline: "from_agent e to_agent devono essere agenti diversi"
type: vincolo
priority: must
stream: "[CORE]"
source: document:REQUEST_board_messages.md
depends: REQ-005
status: proposed
status_date: 2026-03-30
---

Un agente non può mandare un messaggio a sé stesso.
Implementato via CHECK constraint: `from_agent <> to_agent`.

**Accettazione:** `INSERT` con `from_agent = to_agent` fallisce con constraint violation.

---

### REQ-007 — Tipi di messaggio vincolati

---
id: REQ-007
headline: "Tipi di messaggio vincolati a valori predefiniti"
type: vincolo
priority: must
stream: "[CORE]"
source: document:REQUEST_board_messages.md
depends: REQ-005
status: proposed
status_date: 2026-03-30
---

Il campo `type` accetta solo: `task`, `question`, `blocker`, `done`, `alignment_issue`.
Implementato via CHECK constraint.

**Accettazione:** `INSERT` con `type = 'invalid'` fallisce.

---

### REQ-008 — Status del messaggio vincolati con default 'pending'

---
id: REQ-008
headline: "Status del messaggio vincolati con default pending"
type: vincolo
priority: must
stream: "[CORE]"
source: document:REQUEST_board_messages.md
depends: REQ-005
status: proposed
status_date: 2026-03-30
---

Il campo `status` accetta solo: `pending`, `acknowledged`, `in_progress`, `done`, `cancelled`.
Default: `pending`.

**Accettazione:** INSERT senza status → status = 'pending'. INSERT con status = 'invalid' → fallisce.

---

### REQ-009 — ref_id per catene di messaggi

---
id: REQ-009
headline: "ref_id come self-referencing FK per catene di messaggi"
type: funzionale
priority: must
stream: "[CORE]"
source: document:REQUEST_board_messages.md
depends: REQ-005
status: proposed
status_date: 2026-03-30
---

`ref_id` è una FK nullable che punta a `board_messages(id)`.
Usato per messaggi `done` che riferiscono il task originale, o per reply in generale.

**Accettazione:** INSERT con `ref_id` che punta a messaggio esistente → OK. INSERT con `ref_id` inesistente → FK violation.

---

### REQ-010 — Indici per query principali

---
id: REQ-010
headline: "Indici su to_agent+status, from_agent e ref_id"
type: non-funzionale
priority: must
stream: "[CORE]"
source: document:REQUEST_board_messages.md
depends: REQ-005
status: proposed
status_date: 2026-03-30
---

Tre indici per le query operative del Board MCP:
1. `idx_board_messages_to_agent_status` su `(to_agent, status)` — inbox
2. `idx_board_messages_from_agent` su `(from_agent)` — messaggi inviati
3. `idx_board_messages_ref_id` su `(ref_id)` — catene di messaggi

**Accettazione:** I 3 indici esistono e vengono usati nelle query previste (verificabile con EXPLAIN).

---

### REQ-011 — Trigger updated_at automatico

---
id: REQ-011
headline: "Trigger che aggiorna updated_at a now() su ogni UPDATE"
type: funzionale
priority: must
stream: "[CORE]"
source: document:REQUEST_board_messages.md
depends: REQ-005
status: proposed
status_date: 2026-03-30
---

Un trigger BEFORE UPDATE su `board_messages` imposta `updated_at = now()` automaticamente.

**Accettazione:** UPDATE su una riga → `updated_at` cambia al timestamp corrente.

---

### REQ-012 — RLS abilitato con deny-all per anon e authenticated

---
id: REQ-012
headline: "RLS abilitato su entrambe le tabelle con deny-all di default"
type: vincolo
priority: must
stream: "[CORE]"
source: document:REQUEST_board_messages.md, conversation:2026-03-30
depends: REQ-001, REQ-005
status: proposed
status_date: 2026-03-30
---

Sia `board_agents` che `board_messages` hanno RLS abilitato.
Nessuna policy per `anon` o `authenticated` → deny-all di default.
Il Board MCP usa service role key che bypassa RLS nativamente.

**Accettazione:** Query con ruolo `anon` o `authenticated` su entrambe le tabelle → 0 righe.

---

*Generato: 2026-03-30 — DBA, skill requirements-engineer*
*Source: REQUEST_board_messages.md + conversazione con Achille*
