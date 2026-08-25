#!/bin/bash

# This file is sourced by every PostgreSQL benchmark helper.  Keep failures
# visible to the caller: a successful shell command must not hide a failed
# SQL statement or a connection to an unintended PostgreSQL instance.
set -o pipefail

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

# Run psql as the database owner.  PGDATA selects a server data directory for
# pg_ctl, but it does not select the endpoint used by psql.  PGHOST/PGPORT
# (or the PostgreSQL default socket/port when unset) select that endpoint.
postgres_psql() {
    local connection_args=()
    if [[ -n "${PGHOST:-}" ]]; then
        connection_args+=(-h "$PGHOST")
    fi
    if [[ -n "${PGPORT:-}" ]]; then
        connection_args+=(-p "$PGPORT")
    fi
    if [[ -n "${PGUSER:-}" ]]; then
        connection_args+=(-U "$PGUSER")
    fi

    # Root/CI installations commonly allow passwordless sudo to the postgres
    # OS account.  For a local developer PostgreSQL started under another
    # account, allow normal password authentication instead (for example with
    # PGUSER=postgres and PGPASSWORD set in the calling shell).
    if [[ "${PSQL_USE_SUDO:-auto}" != "never" ]] && command -v sudo >/dev/null 2>&1 \
        && sudo -n -u postgres true >/dev/null 2>&1; then
        sudo -u postgres -- "$PSQL_BIN" -X -v ON_ERROR_STOP=1 "${connection_args[@]}" "$@"
    else
        if [[ -z "${PGUSER:-}" ]]; then
            connection_args+=(-U postgres)
        fi
        "$PSQL_BIN" -X -v ON_ERROR_STOP=1 "${connection_args[@]}" "$@"
    fi
}

# Print enough identity information to prove which PostgreSQL instance the
# benchmark is using.  This is deliberately queried through the same helper
# as all benchmark statements.
postgres_server_info() {
    postgres_psql -d postgres -Atqc \
        "SELECT version() || E'\\n' ||
                current_setting('data_directory') || E'\\n' ||
                current_setting('port') || E'\\n' ||
                COALESCE(inet_server_addr()::text, 'unix-socket')"
}
