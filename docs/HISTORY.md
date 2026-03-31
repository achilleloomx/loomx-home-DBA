# HISTORY — LoomX Home DBA

> Storico sessioni del Database Administrator.

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
