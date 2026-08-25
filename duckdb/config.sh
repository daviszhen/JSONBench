#!/bin/bash

# Keep DuckDB database files in a dedicated, git-ignored data directory.
DUCKDB_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DUCKDB_DEFAULT_DATA_DIR="$(cd "$DUCKDB_CONFIG_DIR/.." && pwd -P)/data/duckdb"
DUCKDB_DATA_DIR="${DUCKDB_DATA_DIR:-$DUCKDB_DEFAULT_DATA_DIR}"

duckdb_database_path() {
    local database_name="$1"

    if [[ "$database_name" == /* ]]; then
        printf '%s\n' "$database_name"
    else
        printf '%s/%s\n' "$DUCKDB_DATA_DIR" "$database_name"
    fi
}
