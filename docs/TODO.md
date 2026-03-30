# TODO — LoomX Home DBA

> Task del Database Administrator.

---

## In corso

- [ ] Setup iniziale progetto Supabase (config, primo schema)
- [ ] Migrare schema esistente da loomx-home-app (namespace `home_*`)

## Backlog

- [ ] Definire RLS policies base per namespace `home_*`
- [ ] Procedura registrazione nuovo agente (documentare in docs/)

## Done

- [x] Creare tabelle `board_*` per Board MCP (migrazione `20260330100000`)
- [x] Definire RLS policies per namespace `board_*` (deny-all + service role)
- [x] Documentare schema `board_*` in SCHEMA.md
- [x] Formalizzare requisiti in REQUISITI_board_messages.md

---

*Ultimo aggiornamento: 2026-03-30*
