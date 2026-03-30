# Migration Request: `board_messages`

> **From:** MCP Agent (`loomx-board-mcp`)
> **To:** DBA (`loomx-home-DBA`)
> **Date:** 2026-03-30
> **Priority:** High — blocca lo sviluppo del Board MCP

---

## Cosa serve

Una tabella `board_messages` nel namespace `board_*` per la comunicazione inter-agente.

## Schema richiesto

```sql
CREATE TABLE board_messages (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_agent    TEXT NOT NULL,
  to_agent      TEXT NOT NULL,
  type          TEXT NOT NULL,
  subject       TEXT NOT NULL,
  body          TEXT NOT NULL,
  ref_id        UUID REFERENCES board_messages(id),
  status        TEXT NOT NULL DEFAULT 'pending',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## Vincoli

### `from_agent` e `to_agent`
```sql
CHECK (from_agent IN ('pm', 'app', 'assistant', 'dba'))
CHECK (to_agent IN ('pm', 'app', 'assistant', 'dba'))
CHECK (from_agent <> to_agent)
```

### `type`
```sql
CHECK (type IN ('task', 'question', 'blocker', 'done', 'alignment_issue'))
```

### `status`
```sql
CHECK (status IN ('pending', 'acknowledged', 'in_progress', 'done', 'cancelled'))
```

### `ref_id`
- FK verso `board_messages(id)` — usato per messaggi `done` che riferiscono il task originale
- Nullable

## Indici richiesti

| Indice | Colonne | Motivo |
|---|---|---|
| `idx_board_messages_to_agent_status` | `(to_agent, status)` | Query principale: `board_inbox` filtra per destinatario e status |
| `idx_board_messages_from_agent` | `(from_agent)` | Lookup messaggi inviati |
| `idx_board_messages_ref_id` | `(ref_id)` | Join per catene di messaggi |

## Trigger `updated_at`

Serve un trigger che aggiorni `updated_at` a `now()` su ogni UPDATE:

```sql
CREATE OR REPLACE FUNCTION board_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_board_messages_updated_at
  BEFORE UPDATE ON board_messages
  FOR EACH ROW
  EXECUTE FUNCTION board_update_timestamp();
```

## RLS

Il Board MCP usa la **service role key** (bypass RLS), quindi le policy RLS possono essere restrittive. Suggerimento:

- RLS abilitato sulla tabella
- Policy di default: deny all per `anon` e `authenticated`
- Il service role bypassa RLS nativamente

Il DBA può decidere la strategia RLS più appropriata.

## Operazioni che il MCP esegue

| Operazione | Query |
|---|---|
| `board_send` | `INSERT` con `from_agent = self` |
| `board_inbox` | `SELECT WHERE to_agent = self` (+ filtro status opzionale) |
| `board_ack` | `UPDATE SET status = 'acknowledged' WHERE id = ? AND to_agent = self` |
| `board_update_status` | `UPDATE SET status = ? WHERE id = ? AND to_agent = self` |

## Note

- Il naming della migration deve seguire il pattern `<timestamp>_board_messages.sql`
- Non servono seed data — il board parte vuoto
- In futuro potrebbe servire una tabella `board_attachments` ma per ora non è necessaria

---

*Generato da: loomx-board-mcp, sessione 2026-03-30*
