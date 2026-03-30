# SCHEMA — LoomX Home Database

> Documentazione dello schema Supabase, organizzato per namespace.

---

## Namespace

### `home_` — App famiglia

(da documentare dopo migrazione da loomx-home-app)

### `board_` — Board MCP inter-agente

#### `board_agents`
Registry centralizzato degli agenti. Ogni agente ha un codice numerico progressivo a 3 cifre.

| Colonna | Tipo | Note |
|---|---|---|
| `agent_code` | TEXT PK | Codice numerico: `001`, `002`, ... |
| `slug` | TEXT UNIQUE NOT NULL | Identificativo breve URL-safe |
| `label` | TEXT NOT NULL | Nome esteso leggibile |
| `nickname` | TEXT | Defaults to label via trigger |
| `scope` | TEXT NOT NULL | Descrizione responsabilità |
| `repo` | TEXT | Nome repository associato |
| `active` | BOOLEAN DEFAULT true | Flag attivo/disattivo |
| `created_at` | TIMESTAMPTZ DEFAULT now() | Timestamp creazione |

**Trigger:** `trg_board_agents_default_nickname` — se nickname è NULL, copia label.
**RLS:** Abilitato, deny-all. Accesso solo via service role.

**Agenti registrati:**

| Code | Slug | Label | Nickname |
|---|---|---|---|
| 001 | pm-home | Project Manager — LoomX Home | *(=label)* |
| 002 | dba | Database Administrator — LoomX Home | *(=label)* |
| 003 | app | Product Owner — LoomX Home | *(=label)* |
| 004 | assistant | Home Assistant — LoomX Home | Evaristo |

#### `board_messages`
Messaggi inter-agente per il Board MCP.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | `gen_random_uuid()` |
| `from_agent` | TEXT FK → board_agents | Mittente |
| `to_agent` | TEXT FK → board_agents | Destinatario (≠ from_agent) |
| `type` | TEXT | `task`, `question`, `blocker`, `done`, `alignment_issue` |
| `subject` | TEXT NOT NULL | Oggetto |
| `body` | TEXT NOT NULL | Contenuto |
| `ref_id` | UUID FK → board_messages | Self-ref per catene, nullable |
| `status` | TEXT DEFAULT 'pending' | `pending`, `acknowledged`, `in_progress`, `done`, `cancelled` |
| `created_at` | TIMESTAMPTZ DEFAULT now() | Creazione |
| `updated_at` | TIMESTAMPTZ DEFAULT now() | Ultimo aggiornamento |

**Indici:** `(to_agent, status)`, `(from_agent)`, `(ref_id)`
**Trigger:** `trg_board_messages_updated_at` — aggiorna `updated_at` su ogni UPDATE.
**RLS:** Abilitato, deny-all. Accesso solo via service role.

---

*Ultimo aggiornamento: 2026-03-30*
