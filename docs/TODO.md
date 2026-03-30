# TODO — LoomX Home DBA

> Task del Database Administrator.

---

## In corso

(nessuno)

## Backlog

- [ ] Comunicare al Product Owner (003/app) che le tabelle ora hanno prefisso `home_` — le query nell'app vanno aggiornate

## Done

- [x] Creare tabelle `board_*` per Board MCP (migrazione `20260330100000`)
- [x] Definire RLS policies per namespace `board_*` (deny-all + service role)
- [x] Documentare schema `board_*` in SCHEMA.md
- [x] Formalizzare requisiti in REQUISITI_board_messages.md
- [x] Setup iniziale progetto Supabase (`fvoxccwfysazwpchudwp`, EU West Paris)
- [x] Procedura registrazione nuovo agente (docs/AGENT_REGISTRATION.md)
- [x] Migrare schema `home_*` con prefisso fisico (migrazione `20260330110000`, D-005)
- [x] RLS policies per namespace `home_*` (family-based, `home_get_my_family_id()`)

---

*Ultimo aggiornamento: 2026-03-30*
