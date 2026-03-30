# SCHEMA — LoomX Home Database

> Documentazione dello schema Supabase, organizzato per namespace.

---

## Namespace

### `home_` — App famiglia

> **Nota:** Le tabelle esistenti in loomx-home-app NON hanno prefisso `home_`.
> Decisione pendente: rinominare con prefisso o accettare namespace logico.
> Source: `loomx-home-app/supabase/migrations/001-003`

**Stato:** Non ancora migrato nel progetto DBA. Schema documentato sotto come riferimento.

#### `families`
Nuclei familiari.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `name` | TEXT NOT NULL | |
| `created_at` | TIMESTAMPTZ | |

#### `profiles`
Link utente ↔ famiglia (auth).

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → auth.users | UNIQUE |
| `family_id` | UUID FK → families | |
| `display_name` | TEXT NOT NULL | |
| `role` | TEXT | `admin`, `member` |
| `created_at` | TIMESTAMPTZ | |

#### `family_members`
Componenti del nucleo familiare (non utenti auth, persone reali).

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → families | |
| `name` | TEXT NOT NULL | |
| `age` | INTEGER NOT NULL | |
| `sex` | TEXT | `M`, `F` |
| `role` | TEXT | `adult`, `child`, `infant` |
| `dietary_notes` | TEXT | |
| `conditions` | TEXT[] | Default `{}` |
| `is_active` | BOOLEAN | Default true |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

#### `pets`
Animali domestici.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → families | |
| `name`, `species` | TEXT NOT NULL | |
| `breed` | TEXT | |
| `weight_kg` | NUMERIC(5,2) | |
| `diet_notes` | TEXT | |
| `created_at` | TIMESTAMPTZ | |

#### `shopping_categories`
Categorie della spesa (per famiglia, con default via seed function).

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → families | |
| `name` | TEXT NOT NULL | |
| `sort_order` | INTEGER | |
| `is_default` | BOOLEAN | |
| `created_at` | TIMESTAMPTZ | |

#### `shopping_lists`
Liste della spesa settimanali.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → families | |
| `name` | TEXT | Default 'Lista della spesa' |
| `week_start` | DATE | |
| `is_active` | BOOLEAN | |
| `created_at` | TIMESTAMPTZ | |

#### `shopping_items`
Singoli articoli nella lista della spesa.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `list_id` | UUID FK → shopping_lists | CASCADE |
| `category_id` | UUID FK → shopping_categories | |
| `product_name` | TEXT NOT NULL | |
| `quantity` | NUMERIC(8,2) | Default 1 |
| `unit` | TEXT | Default 'pz' |
| `notes` | TEXT | |
| `is_checked` | BOOLEAN | |
| `checked_at` | TIMESTAMPTZ | |
| `checked_by` | UUID FK → auth.users | |
| `added_by` | UUID FK → auth.users | NOT NULL |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

#### `purchase_history`
Storico acquisti.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → families | |
| `product_name` | TEXT NOT NULL | |
| `quantity` | NUMERIC(8,2) | |
| `unit` | TEXT | Default 'pz' |
| `purchased_at` | TIMESTAMPTZ | |
| `store` | TEXT | |
| `purchased_by` | UUID FK → auth.users | |
| `created_at` | TIMESTAMPTZ | |

#### `weekly_menus`
Menù settimanali.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → families | |
| `week_start` | DATE NOT NULL | UNIQUE con family_id |
| `status` | TEXT | `draft`, `approved` |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

#### `menu_items`
Piatti nel menù.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `menu_id` | UUID FK → weekly_menus | CASCADE |
| `day_of_week` | INTEGER | 0-6 |
| `meal_type` | TEXT | `breakfast`, `lunch`, `dinner`, `snack` |
| `dish_name` | TEXT NOT NULL | |
| `ingredients` | JSONB | |
| `covered_by_school` | BOOLEAN | Default false |
| `member_ids` | UUID[] | Default `{}` |
| `notes` | TEXT | |
| `created_at` | TIMESTAMPTZ | |

**RLS:** Tutte le tabelle hanno RLS abilitato. Policy basate su `get_my_family_id()` (helper function). `authenticated` ha accesso filtrato per famiglia, `anon` ha zero accesso.

**Function:** `seed_default_categories(family_id)` — seed 11 categorie spesa default per nuove famiglie.

**GRANT:** `authenticated` ha SELECT/INSERT/UPDATE/DELETE su tutte le tabelle (tranne `purchase_history`: solo SELECT/INSERT).

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
