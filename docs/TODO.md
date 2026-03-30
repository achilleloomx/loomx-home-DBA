# TODO — LoomX Home DBA

> Task del Database Administrator.

---

## Bloccati — serve decisione

- [ ] **Migrare schema `home_*` da loomx-home-app** — le tabelle esistenti (families, profiles, shopping_lists, ecc.) non hanno prefisso `home_`. Serve decidere: rinominare con prefisso (breaking change) o accettare namespace logico senza prefisso fisico?
- [ ] Definire RLS policies base per namespace `home_*` (bloccato da migrazione)

## In corso

(nessuno)

## Backlog

(nessuno)

## Done

- [x] Creare tabelle `board_*` per Board MCP (migrazione `20260330100000`)
- [x] Definire RLS policies per namespace `board_*` (deny-all + service role)
- [x] Documentare schema `board_*` in SCHEMA.md
- [x] Formalizzare requisiti in REQUISITI_board_messages.md
- [x] Setup iniziale progetto Supabase (`fvoxccwfysazwpchudwp`, EU West Paris)
- [x] Procedura registrazione nuovo agente (docs/AGENT_REGISTRATION.md)

---

*Ultimo aggiornamento: 2026-03-30*
