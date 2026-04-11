# SCHEMA — LoomX Home Database

> Documentazione dello schema Supabase, organizzato per namespace.

---

## Namespace

### `home_` — App famiglia

**Migrazione:** `20260330110000_home_schema.sql` — D-005
**Stato:** Live su Supabase.

#### `home_families`
Nuclei familiari.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `name` | TEXT NOT NULL | |
| `created_at` | TIMESTAMPTZ | |

#### `home_profiles`
Link utente ↔ famiglia (auth).

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → auth.users | UNIQUE |
| `family_id` | UUID FK → families | |
| `display_name` | TEXT NOT NULL | |
| `role` | TEXT | `admin`, `member` |
| `created_at` | TIMESTAMPTZ | |

#### `home_family_members`
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

#### `home_pets`
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

#### `home_shopping_categories`
Categorie della spesa (per famiglia, con default via seed function).

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → families | |
| `name` | TEXT NOT NULL | |
| `sort_order` | INTEGER | |
| `is_default` | BOOLEAN | |
| `created_at` | TIMESTAMPTZ | |

#### `home_shopping_lists`
Liste della spesa settimanali.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → families | |
| `name` | TEXT | Default 'Lista della spesa' |
| `week_start` | DATE | |
| `is_active` | BOOLEAN | |
| `created_at` | TIMESTAMPTZ | |

#### `home_shopping_items`
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
| `from_menu` | BOOLEAN NOT NULL | Default `false`. `true` se l'item proviene dal menu settimanale (icona dedicata in UI). D-030. |
| `status` | TEXT NOT NULL | Default `'active'`. CHECK IN (`'active'`, `'proposed'`). `proposed` = item proposto da Evaristo in attesa di review utente nella sotto-sezione "Proposta di Evaristo". D-030. |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

Indice: `idx_home_shopping_items_list_status (list_id, status)` per split-view active/proposed.

#### `home_purchase_history`
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

#### `home_weekly_menus`
Menù settimanali.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → families | |
| `week_start` | DATE NOT NULL | UNIQUE con family_id |
| `status` | TEXT | `draft`, `approved` |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

#### `home_menu_items`
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

#### `home_school_menus`
Menù scolastici per bambini (import manuale o scraper).

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `family_id` | UUID FK → home_families | CASCADE |
| `member_id` | UUID FK → home_family_members | CASCADE |
| `week_start` | DATE NOT NULL | |
| `day_of_week` | INTEGER | 0-4 (lun-ven) |
| `dish_name` | TEXT NOT NULL | |
| `dish_details` | TEXT | |
| `source` | TEXT | `manual`, `scraper`. Default `manual` |
| `created_at` | TIMESTAMPTZ | |

**UNIQUE:** `(family_id, member_id, week_start, day_of_week)`

**RLS:** Tutte le tabelle hanno RLS abilitato. Policy basate su `home_get_my_family_id()` (helper function). `authenticated` ha accesso filtrato per famiglia, `anon` ha zero accesso.

**Function:** `home_seed_default_categories(family_id)` — seed 11 categorie spesa default per nuove famiglie.

**GRANT:** `authenticated` ha SELECT/INSERT/UPDATE/DELETE su tutte le tabelle (tranne `home_purchase_history`: solo SELECT/INSERT).

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
| 001 | loomy | Loomy — LoomX Root Coordinator | Loomy |
| 002 | dba | Database Administrator — LoomX Home | *(=label)* |
| 003 | app | Product Owner — LoomX Home | *(=label)* |
| 004 | assistant | Home Assistant — LoomX Home | Evaristo |
| 005 | board-mcp | Board MCP Server — LoomX Home | Postman |
| 010 | sito-loomx | Product Owner — Sito LoomX | Sito LoomX |
| 011 | loomx-commercialisti | Product Owner — LoomX Commercialisti | Commercialisti |
| 012 | damato | Product Owner — D'Amato Arredamenti | D'Amato |
| 013 | sintesi-impianti | Consulting — Sintesi Impianti | Sintesi |

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
| `tags` | TEXT[] DEFAULT '{}' | Tag per topic filtering |
| `summary` | TEXT | Riassunto breve per risparmio token |
| `archived_at` | TIMESTAMPTZ | NULL = attivo, valorizzato = archiviato |
| `created_at` | TIMESTAMPTZ DEFAULT now() | Creazione |
| `updated_at` | TIMESTAMPTZ DEFAULT now() | Ultimo aggiornamento |

**Indici:** `(to_agent, status)`, `(from_agent)`, `(ref_id)`, `GIN(tags)`, `(archived_at) WHERE NULL`
**Trigger:** `trg_board_messages_updated_at` — aggiorna `updated_at` su ogni UPDATE.
**Function:** `board_broadcast(from, type, subject, body, ref_id)` — invia a tutti gli agenti attivi.
**Function:** `board_archive_old(days DEFAULT 7)` — archivia messaggi done/cancelled più vecchi di N giorni.
**View:** `board_overview` — JOIN con board_agents, esclude archiviati. Include summary, tags.
**RLS:** Abilitato, deny-all. Accesso solo via service role.

### `loomx_` — Root agent Loomy (anagrafica, GTD, documenti)

**Migrazione:** `20260405100000_loomx_namespace_and_agent_updates.sql` — D-007, D-008
**Stato:** Da applicare su Supabase.

#### `loomx_clients`
Anagrafica clienti LoomX.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `name` | TEXT NOT NULL | |
| `short_name` | TEXT UNIQUE | |
| `sector` | TEXT | |
| `size` | TEXT | e.g. '1-10M', '10-50M' |
| `contact_email` | TEXT | |
| `contact_name` | TEXT | |
| `notes` | TEXT | |
| `status` | TEXT | `active`, `inactive`, `prospect`. Default `active` |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

#### `loomx_projects`
Progetti LoomX con link a cliente e agente responsabile.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `name` | TEXT NOT NULL | |
| `short_name` | TEXT UNIQUE | |
| `client_id` | UUID FK → loomx_clients | |
| `type` | TEXT | `consulting`, `tech`, `personal`, `presales`, `internal` |
| `agent_id` | TEXT | slug dell'agente responsabile |
| `repo` | TEXT | GitHub repo name |
| `local_path` | TEXT | Path locale filesystem |
| `status` | TEXT | `active`, `paused`, `done`, `archived`. Default `active` |
| `notes` | TEXT | |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

#### `loomx_tags`
Tag per categorizzazione items. Dimensione condivisa (lettura per tutti gli authenticated).

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | DEFAULT `gen_random_uuid()` |
| `name` | TEXT UNIQUE NOT NULL | |
| `color` | TEXT | Hex color usato dall'UI GTD per il chip |
| `description` | TEXT | Semantica/regole d'uso. D-028 |
| `created_at` | TIMESTAMPTZ NOT NULL | DEFAULT `now()`. D-028 |

**Tag riservati:**
- `famiglia` *(D-027)* — visibilità di gruppo: items con questo tag sono visibili a tutti gli `loomx_owner_auth.is_family=true`.

#### `loomx_items`
GTD items — task management centralizzato (D-004 hub).

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `title` | TEXT NOT NULL | |
| `body` | TEXT | |
| `gtd_status` | TEXT | `inbox`, `next_action`, `waiting`, `scheduled`, `in_progress`, `someday`, `done`, `trash`. Default `inbox` |
| `owner` | TEXT | agent_id o 'achille' |
| `waiting_on` | TEXT | Chi si sta aspettando |
| `priority` | TEXT | `low`, `normal`, `high`, `urgent`. Default `normal` |
| `deadline` | TIMESTAMPTZ | |
| `completed_at` | TIMESTAMPTZ | |
| `context` | TEXT | Contesto GTD: `@casa`, `@ufficio`, etc. Testo libero (no FK). D-024 |
| `time_estimate` | SMALLINT | Minuti stimati: 5, 15, 30, 60, 120. CHECK constraint. D-024 |
| `energy_level` | SMALLINT | 1=bassa, 2=media, 3=alta. CHECK 1-3. D-024 |
| `deleted_at` | TIMESTAMPTZ | Soft-delete timestamp. Retention 7gg, poi hard-delete via cron. D-024 |
| `clarified_at` | TIMESTAMPTZ | Quando l'item esce da inbox. Metrica time-to-clarify. D-024 |
| `project_id` | UUID FK → loomx_gtd_projects | GTD project (1:N). ON DELETE SET NULL. D-024 |
| `source` | TEXT | Provenienza: meeting, email, board, manual |
| `source_ref` | TEXT | Riferimento sorgente |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

#### `loomx_item_projects`
Mapping N:N tra items e progetti.

| Colonna | Tipo | Note |
|---|---|---|
| `item_id` | UUID FK → loomx_items | CASCADE |
| `project_id` | UUID FK → loomx_projects | CASCADE |

**PK composita:** `(item_id, project_id)`

#### `loomx_item_tags`
Mapping N:N tra items e tags.

| Colonna | Tipo | Note |
|---|---|---|
| `item_id` | UUID FK → loomx_items | CASCADE |
| `tag_id` | UUID FK → loomx_tags | CASCADE |

**PK composita:** `(item_id, tag_id)`

#### `loomx_documents`
Indice documenti per progetto/agente.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `path` | TEXT UNIQUE NOT NULL | |
| `filename` | TEXT NOT NULL | |
| `doc_type` | TEXT | md, pdf, xlsx, etc. |
| `title` | TEXT | |
| `description` | TEXT | |
| `project_id` | UUID FK → loomx_projects | |
| `agent_id` | TEXT | slug dell'agente owner |
| `status` | TEXT | `active`, `archived`, `deleted`. Default `active` |
| `size_bytes` | BIGINT | |
| `last_modified` | TIMESTAMPTZ | |
| `indexed_at` | TIMESTAMPTZ | |

#### Views

- **`loomx_v_inbox`** — Items con `gtd_status = 'inbox'`, con project_ids aggregati. Ordinati per priority DESC, created_at.
- **`loomx_v_next_actions`** — Items con `gtd_status = 'next_action'`. Ordinati per priority DESC, deadline.
- **`loomx_v_waiting_for`** — Items con `gtd_status = 'waiting_for'`. Ordinati per deadline.
- **`loomx_v_project_dashboard`** — Conteggio items per progetto e gtd_status.

#### `loomx_gtd_projects` *(D-024)*
Progetti GTD (outcome multi-step personali). Separati da `loomx_projects` (anagrafica org).

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `title` | TEXT NOT NULL | |
| `description` | TEXT | |
| `owner` | TEXT NOT NULL | slug |
| `status` | TEXT NOT NULL | `active`, `completed`, `on_hold`, `dropped`. Default `active` |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

#### `loomx_contexts` *(D-024)*
Contesti GTD custom per owner. Catalogo dropdown, non vincolante su loomx_items.

| Colonna | Tipo | Note |
|---|---|---|
| `id` | UUID PK | |
| `name` | TEXT NOT NULL | e.g. `@casa`, `@palestra` |
| `owner` | TEXT NOT NULL | slug |
| `is_default` | BOOLEAN | Default false |
| `sort_order` | SMALLINT | Default 0 |
| `created_at` | TIMESTAMPTZ | |

**UNIQUE:** `(owner, name)`

#### `loomx_owner_auth` *(D-024, esteso D-027)*
Mapping owner slug <-> Supabase Auth UUID. Flag `is_pmo` per visibilita' cross-owner, flag `is_family` per visibilità di gruppo (D-027).

| Colonna | Tipo | Note |
|---|---|---|
| `owner_slug` | TEXT PK | 'achille', 'loomy', etc. |
| `user_id` | UUID UNIQUE | FK auth.users. NULL per agenti |
| `is_pmo` | BOOLEAN NOT NULL | Default false. PMO = SELECT all items |
| `is_family` | BOOLEAN NOT NULL | Default false. Family member = vede gli items taggati `famiglia` (D-027). Oggi: achille, vanessa. |
| `created_at` | TIMESTAMPTZ | |

#### `loomx_item_agents` *(D-018, esteso D-026)*
Co-engagement N:N item-subject (AI agent o persona). Mappa RACI:
- `collaborator` = R/A — read + write
- `watcher` = I — read-only (Informed)

| Colonna | Tipo | Note |
|---|---|---|
| `item_id` | UUID FK → loomx_items | CASCADE |
| `agent_slug` | TEXT NOT NULL | Slug subject (board_agents.slug **o** loomx_owner_auth.owner_slug). FK rimossa in D-026. |
| `role` | TEXT NOT NULL | CHECK `role IN ('collaborator','watcher')` (D-026). Default 'collaborator'. |
| `added_by` | TEXT NOT NULL | slug agente/persona che ha aggiunto il link |
| `added_at` | TIMESTAMPTZ | |

**PK composita:** `(item_id, agent_slug)`

#### Functions *(D-024, esteso D-026)*

- **`loomx_get_owner_slug()`** — SECURITY DEFINER. Restituisce lo slug dell'utente autenticato corrente leggendo `loomx_owner_auth`.
- **`loomx_is_pmo()`** — SECURITY DEFINER. Restituisce `true` se l'utente corrente ha flag `is_pmo`.
- **`loomx_item_owner(uuid) → text`** *(D-026)* — SECURITY DEFINER. Owner di un item GTD bypassando RLS (anti-recursion nelle policy `loomx_item_agents`).
- **`loomx_user_engaged_role(uuid) → text`** *(D-026)* — SECURITY DEFINER. Restituisce `collaborator`/`watcher`/`NULL` per il current user su un item, bypassando RLS.
- **`loomx_is_family_member()`** *(D-027)* — SECURITY DEFINER. Restituisce `true` se l'utente corrente ha flag `is_family`.
- **`loomx_item_has_family_tag(uuid) → bool`** *(D-027)* — SECURITY DEFINER. `true` se l'item ha il tag `famiglia`. Bypassa RLS di `loomx_item_tags`/`loomx_tags`.

#### RLS (`loomx_*`)

**Pre-D-024:** Deny-all (nessuna policy esplicita). Accesso solo via service role (D-008).

**Post-D-024 + D-025 + D-026:** Policy per `authenticated` (utenti PWA):
- `loomx_items`:
  - `SELECT`: PMO vede tutto, owner vede i propri, **co-engaged (collaborator OR watcher) vedono gli item linkati** *(D-026)*, **family member vede gli items taggati `famiglia`** *(D-027)*
  - `INSERT`: PMO override *(D-029)*, come se stesso, o whitelist dispatcher `{loomy, assistant, achille}` *(D-029 + D-030)*. Nota: `INSERT ... RETURNING` cross-owner viene rifiutato dalla SELECT visibility — usare INSERT senza RETURNING o accettare il rifiuto come read-only.
  - `UPDATE`: PMO *(D-025)*, owner, o **collaborator (NOT watcher)** *(D-026)*
  - `DELETE`: PMO *(D-025)* o owner. Watcher e collaborator NON cancellano.
- `loomx_tags` *(D-027)*:
  - `SELECT`: tutti gli authenticated (dimensione condivisa)
  - `INSERT`/`UPDATE`/`DELETE`: solo PMO
- `loomx_item_tags` *(D-027)*:
  - `SELECT`: PMO, owner del parent item, co-engaged, o family member su item taggato `famiglia`
  - `INSERT`/`DELETE`: PMO o owner del parent item
- `loomx_gtd_projects`: PMO override su UPDATE/DELETE *(D-025)*, INSERT solo come sé.
- `loomx_contexts`: CRUD solo propri.
- `loomx_owner_auth`: SELECT solo la propria riga.
- `loomx_item_projects`: SELECT filtrato per visibilita' items.
- `loomx_projects` (org): SELECT read-only per PMO.
- `loomx_item_agents` *(D-026)*:
  - `SELECT`: PMO, subject del link, o owner dell'item linkato
  - `INSERT/DELETE`: PMO o owner dell'item linkato

Policy per-agent (doc_researcher etc.) restano invariate e additive (nota: `doc_researcher_update_engaged` non filtra per `role` — vedi D-026 follow-up).

---

*Ultimo aggiornamento: 2026-04-11 (D-027)*
