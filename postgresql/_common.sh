#!/bin/bash

# Resolve the PostgreSQL client without changing the host installation.  The
# PGDG RPM layout used by the benchmark server is /usr/pgsql-16/bin, while
# distribution packages normally put psql on PATH.
psql_candidate="${PSQL_BIN:-}"
if [[ -z "$psql_candidate" && -n "${PG_BIN:-}" ]]; then
    psql_candidate="$PG_BIN/psql"
fi
if [[ -z "$psql_candidate" && -x /usr/pgsql-16/bin/psql ]]; then
    psql_candidate=/usr/pgsql-16/bin/psql
fi
if [[ -z "$psql_candidate" ]]; then
    psql_candidate="$(command -v psql 2>/dev/null || true)"
fi
if [[ "$psql_candidate" != */* ]]; then
    psql_candidate="$(command -v "$psql_candidate" 2>/dev/null || true)"
fi

if [[ -z "$psql_candidate" || ! -x "$psql_candidate" ]]; then
    echo "Error: PostgreSQL client not found. Set PG_BIN or PSQL_BIN before running the benchmark." >&2
    return 1
fi

PSQL_BIN="$psql_candidate"
export PSQL_BIN

# Run psql as the database owner.  PGDATA selects the server data directory
# for pg_ctl; PGHOST/PGPORT select the endpoint used by this client.
postgres_psql() {
    local connection_args=()
    if [[ -n "${PGHOST:-}" ]]; then
        connection_args+=(-h "$PGHOST")
    fi
    if [[ -n "${PGPORT:-}" ]]; then
        connection_args+=(-p "$PGPORT")
    fi
    sudo -u postgres "$PSQL_BIN" "${connection_args[@]}" "$@"
}
