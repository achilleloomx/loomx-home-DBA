# Procedura Registrazione Nuovo Agente

> Come registrare un nuovo agente nel sistema LoomX Home.

---

## Prerequisiti

- Accesso al repo `loomx-home-DBA`
- Accesso al CLAUDE.md del nuovo agente

---

## Procedura

### 1. Assegnare il codice

Il DBA assegna il prossimo codice numerico progressivo a 3 cifre.

Per trovare l'ultimo codice assegnato:

```sql
SELECT agent_code FROM board_agents ORDER BY agent_code DESC LIMIT 1;
```

Il nuovo codice è `ultimo + 1`, zero-padded (es. `004` → `005`).

### 2. Raccogliere i dati

| Campo | Obbligatorio | Descrizione |
|---|---|---|
| `agent_code` | Sì | Codice numerico progressivo (es. `005`) |
| `slug` | Sì | Identificativo breve URL-safe, unico (es. `analytics`) |
| `label` | Sì | Nome esteso leggibile (es. `Analytics Agent — LoomX Home`) |
| `nickname` | No | Nome amichevole. Se omesso, sarà uguale a `label` |
| `scope` | Sì | Descrizione responsabilità (es. `Analisi dati e reporting`) |
| `repo` | No | Nome del repository (es. `loomx-home-analytics`) |

### 3. Creare la migrazione

Il DBA crea una nuova migrazione in `supabase/migrations/`:

```sql
-- Migration: register agent <SLUG>
-- Date: <YYYY-MM-DD>

INSERT INTO board_agents (agent_code, slug, label, nickname, scope, repo)
VALUES ('<CODE>', '<SLUG>', '<LABEL>', <NICKNAME_OR_NULL>, '<SCOPE>', '<REPO>');
```

Naming file: `<timestamp>_board_register_<slug>.sql`

### 4. Applicare la migrazione

```bash
npx supabase db push
```

### 5. Aggiornare il CLAUDE.md del nuovo agente

Aggiungere il blocco identità in testa al CLAUDE.md del nuovo agente:

```markdown
## Identità agente

- **Code:** <CODE>
- **Slug:** <SLUG>
- **Label:** <LABEL>
- **Nickname:** <NICKNAME o —>
```

### 6. Aggiornare la governance DBA

Nel repo `loomx-home-DBA`:

1. **CLAUDE.md** — aggiungere riga nella tabella Coordinamento
2. **docs/SCHEMA.md** — aggiungere riga nella tabella "Agenti registrati"

### 7. Commit e push

Committare la migrazione e gli aggiornamenti governance nel repo DBA.

---

## Esempio completo

Registrazione di un ipotetico agente Analytics:

```
Code:     005
Slug:     analytics
Label:    Analytics Agent — LoomX Home
Nickname: (null → "Analytics Agent — LoomX Home")
Scope:    Analisi dati, reporting, dashboard
Repo:     loomx-home-analytics
```

---

*Creato: 2026-03-30*
