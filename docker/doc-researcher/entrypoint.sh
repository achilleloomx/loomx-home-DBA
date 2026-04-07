#!/usr/bin/env bash
# entrypoint.sh — doc-researcher container
# Responsabilità:
#  1. Configurare Bitwarden CLI sul cluster EU (D-014)
#  2. Login con API key (BW_CLIENTID/BW_CLIENTSECRET) — non interattivo
#  3. Unlock con master password (BW_PASSWORD) → BW_SESSION
#  4. Recupera password DB doc_researcher dal vault → file in tmpfs
#  5. Genera .mcp.json a runtime in tmpfs (mai committato, mai su disco persistente)
#  6. Lock vault e exec del CLI Claude
#
# Le secrets vivono solo in $RUNTIME_DIR (tmpfs) e in env del processo.
# Smoke mode: SMOKE=1 → eseguito senza bw, stampa diagnostica e termina.

set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*" >&2; }

if [[ "${SMOKE:-0}" == "1" ]]; then
  log "SMOKE mode: skipping bw login/unlock"
  log "user=$(id -un) uid=$(id -u)"
  log "node=$(node --version)"
  log "bw=$(bw --version 2>/dev/null || echo MISSING)"
  log "psql=$(psql --version)"
  log "python=$(python3 --version)"
  log "claude=$(claude --version 2>/dev/null || echo MISSING)"
  log "RUNTIME_DIR=$RUNTIME_DIR ($(stat -c '%a %U' "$RUNTIME_DIR" 2>/dev/null || echo n/a))"
  log "smoke OK"
  exit 0
fi

: "${BW_CLIENTID:?BW_CLIENTID env required}"
: "${BW_CLIENTSECRET:?BW_CLIENTSECRET env required}"
: "${BW_PASSWORD:?BW_PASSWORD env required}"
: "${AGENT_SLUG:=doc_researcher}"
: "${BW_VAULT_ITEM:=loomx/agents/${AGENT_SLUG}}"
: "${SUPABASE_HOST:=aws-1-eu-west-3.pooler.supabase.com}"
: "${SUPABASE_PORT:=5432}"
: "${SUPABASE_DB:=postgres}"
: "${SUPABASE_PROJECT_REF:=fvoxccwfysazwpchudwp}"
# Supavisor session-mode requires user format <role>.<project_ref>
PG_USER="${AGENT_SLUG}.${SUPABASE_PROJECT_REF}"

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"

# D-014: vault EU obbligatorio PRIMA di login
log "configuring bw server: https://vault.bitwarden.eu"
bw config server https://vault.bitwarden.eu >/dev/null

log "bw login (apikey)"
bw login --apikey >/dev/null

log "bw unlock"
BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw)"
export BW_SESSION

log "fetching DB password for ${BW_VAULT_ITEM}"
# Item is a Secure Note (type=2): the password lives in `notes`, last line
# (convention: free-form notes followed by a final newline + the password).
# `bw get password` only works for Login items, so parse notes via JSON.
DB_PASSWORD="$(bw get item "$BW_VAULT_ITEM" | python3 -c "import json,sys; print(json.load(sys.stdin)['notes'].rsplit('\n',1)[-1])")"
if [[ -z "$DB_PASSWORD" ]]; then
  log "FATAL: empty DB password from vault item ${BW_VAULT_ITEM}"
  exit 1
fi
printf '%s' "$DB_PASSWORD" > "$RUNTIME_DIR/db_password"
chmod 600 "$RUNTIME_DIR/db_password"

# libpq PGPASSFILE format: host:port:db:user:password
# user must be the Supavisor-prefixed form (PG_USER), not the bare role.
PGPASSFILE="$RUNTIME_DIR/.pgpass"
printf '%s:%s:%s:%s:%s\n' \
  "$SUPABASE_HOST" "$SUPABASE_PORT" "$SUPABASE_DB" "$PG_USER" "$DB_PASSWORD" \
  > "$PGPASSFILE"
chmod 600 "$PGPASSFILE"
export PGPASSFILE

# .mcp.json runtime (template minimo — espandere quando il ruolo entra in prod)
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

# Lock vault — la session key resta in env del solo processo corrente
bw lock >/dev/null || true
unset BW_PASSWORD BW_CLIENTSECRET DB_PASSWORD

# Live smoke: prove auth + RLS + GRANT/DENY end-to-end and exit (no claude exec).
if [[ "${SMOKE_LIVE:-0}" == "1" ]]; then
  log "SMOKE_LIVE: running RLS allow/deny matrix"
  psql "host=${SUPABASE_HOST} port=${SUPABASE_PORT} dbname=${SUPABASE_DB} user=${PG_USER} sslmode=require" \
    -v ON_ERROR_STOP=0 -A -t -c "select 'session_user=' || session_user || ' current_user=' || current_user"
  log "smoke_live OK"
  exit 0
fi

log "entrypoint ready, exec: $*"
exec "$@"
