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

# PGDG installs each client version with a matching libpq.  A machine that
# also has another PostgreSQL client installed can otherwise resolve psql's
# lazy libpq symbols from the wrong major version (for example PG13's library
# with a PG16 psql), which may only fail when psql reconnects.  Prefer an
# explicitly supplied library directory, then infer the sibling lib directory
# only when it actually contains libpq.
psql_library_path="${PSQL_LD_LIBRARY_PATH:-}"
if [[ -z "$psql_library_path" && -n "${PSQL_LIB_DIR:-}" ]]; then
    psql_library_path="$PSQL_LIB_DIR"
fi
if [[ -z "$psql_library_path" ]]; then
    psql_bin_dir=$(cd -- "$(dirname -- "$PSQL_BIN")" && pwd)
    psql_prefix=$(cd -- "$psql_bin_dir/.." && pwd)
    if [[ -d "$psql_prefix/lib" ]] && compgen -G "$psql_prefix/lib/libpq.so*" >/dev/null; then
        psql_library_path="$psql_prefix/lib"
    fi
fi
if [[ -n "$psql_library_path" && -n "${LD_LIBRARY_PATH:-}" ]]; then
    psql_library_path="$psql_library_path:$LD_LIBRARY_PATH"
fi
export PSQL_LD_LIBRARY_PATH="$psql_library_path"

# Run psql as the database owner.  PGDATA selects a server data directory for
# pg_ctl, but it does not select the endpoint used by psql.  PGHOST/PGPORT
# (or the PostgreSQL default socket/port when unset) select that endpoint.
postgres_psql() {
    local connection_args=()
    local psql_command=("$PSQL_BIN")
    if [[ -n "${PSQL_LD_LIBRARY_PATH:-}" ]]; then
        psql_command=(env "LD_LIBRARY_PATH=$PSQL_LD_LIBRARY_PATH" "$PSQL_BIN")
    fi
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
        sudo -u postgres -- "${psql_command[@]}" -X -v ON_ERROR_STOP=1 "${connection_args[@]}" "$@"
    else
        if [[ -z "${PGUSER:-}" ]]; then
            connection_args+=(-U postgres)
        fi
        "${psql_command[@]}" -X -v ON_ERROR_STOP=1 "${connection_args[@]}" "$@"
    fi
}

# Print enough identity information to prove which PostgreSQL instance the
# benchmark is using.  This is deliberately queried through the same helper
# as all benchmark statements.
postgres_server_info() {
    postgres_psql -d postgres -Atqc \
        "SELECT version() || E'\\n' ||
                COALESCE(NULLIF(current_setting('data_directory', true), ''), '<unknown>') || E'\\n' ||
                current_setting('port') || E'\\n' ||
                COALESCE(inet_server_addr()::text, 'unix-socket')"
}
