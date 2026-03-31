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

---

*Watermark: D-006*
