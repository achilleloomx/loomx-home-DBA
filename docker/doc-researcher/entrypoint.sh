#!/usr/bin/env bash
# entrypoint.sh — doc-researcher container (Design C, D-022)
#
# Il container NON parla con Bitwarden. Il launcher sull'host (agent_manager.py)
# estrae la password DB dal vault e la inietta come env var $DB_PASSWORD.
# Conseguenze: niente bw nel container, niente master password mai presente,
# blast radius limitato al singolo segreto operativo del ruolo doc_researcher.
#
# Responsabilità entrypoint:
#  1. Validare $DB_PASSWORD ricevuto dall'host
#  2. Scrivere PGPASSFILE in tmpfs ($RUNTIME_DIR)
#  3. Generare .mcp.json a runtime
#  4. exec del CLI Claude (o smoke test)
#
# Modi:
#  SMOKE=1       → diagnostica struttura, niente DB, exit 0
#  SMOKE_LIVE=1  → connessione reale al DB, verifica session_user, exit 0
#  (default)     → exec "$@"  (di norma `claude`)

set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*" >&2; }

# ---- SMOKE (struttura, no DB) ----
if [[ "${SMOKE:-0}" == "1" ]]; then
  log "SMOKE mode: skipping DB connection"
  log "user=$(id -un) uid=$(id -u)"
  log "node=$(node --version)"
  log "psql=$(psql --version)"
  log "python=$(python3 --version)"
  log "claude=$(claude --version 2>/dev/null || echo MISSING)"
  log "RUNTIME_DIR=$RUNTIME_DIR ($(stat -c '%a %U' "$RUNTIME_DIR" 2>/dev/null || echo n/a))"
  log "smoke OK"
  exit 0
fi

# ---- Required inputs from host launcher ----
: "${DB_PASSWORD:?DB_PASSWORD env required (host launcher must fetch it from the vault)}"
: "${AGENT_SLUG:=doc_researcher}"
: "${SUPABASE_HOST:=aws-1-eu-west-3.pooler.supabase.com}"
: "${SUPABASE_PORT:=5432}"
: "${SUPABASE_DB:=postgres}"
: "${SUPABASE_PROJECT_REF:=fvoxccwfysazwpchudwp}"
# Supavisor session-mode requires user format <role>.<project_ref>
PG_USER="${AGENT_SLUG}.${SUPABASE_PROJECT_REF}"

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"

# libpq PGPASSFILE format: host:port:db:user:password
PGPASSFILE="$RUNTIME_DIR/.pgpass"
printf '%s:%s:%s:%s:%s\n' \
  "$SUPABASE_HOST" "$SUPABASE_PORT" "$SUPABASE_DB" "$PG_USER" "$DB_PASSWORD" \
  > "$PGPASSFILE"
chmod 600 "$PGPASSFILE"
export PGPASSFILE

# .mcp.json runtime — solo lettura per il tooling, mai persistito
cat > "$RUNTIME_DIR/.mcp.json" <<JSON
{
  "mcpServers": {
    "supabase-doc": {
      "command": "psql",
      "args": [
        "-h", "${SUPABASE_HOST}",
        "-p", "${SUPABASE_PORT}",
        "-U", "${PG_USER}",
        "-d", "${SUPABASE_DB}",
        "--set=sslmode=require"
      ]
    }
  }
}
JSON
chmod 600 "$RUNTIME_DIR/.mcp.json"

# DB_PASSWORD ora è in PGPASSFILE (chmod 600 in tmpfs), non serve più in env
unset DB_PASSWORD

# ---- SMOKE_LIVE (DB reale, verifica RLS basics) ----
if [[ "${SMOKE_LIVE:-0}" == "1" ]]; then
  log "SMOKE_LIVE: connecting via Supavisor session-mode"
  psql "host=${SUPABASE_HOST} port=${SUPABASE_PORT} dbname=${SUPABASE_DB} user=${PG_USER} sslmode=require" \
    -v ON_ERROR_STOP=1 -A -t -c "select 'session_user=' || session_user || ' current_user=' || current_user"
  log "smoke_live OK"
  exit 0
fi

log "entrypoint ready, exec: $*"
exec "$@"
