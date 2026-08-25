#!/bin/bash

set -Eeuo pipefail

# Check if the required arguments are provided
if [[ $# -lt 7 ]]; then
    echo "Usage: $0 <DB_NAME> <TABLE_NAME> <DDL_FILE> <DATA_DIRECTORY> <NUM_FILES> <SUCCESS_LOG> <ERROR_LOG>"
    exit 1
fi

# Arguments
DB_NAME="$1"
TABLE_NAME="$2"
DDL_FILE="$3"
DATA_DIRECTORY="$4"
NUM_FILES="$5"
SUCCESS_LOG="$6"
ERROR_LOG="$7"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh" || exit 1

# Validate arguments
[[ ! -f "$DDL_FILE" ]] && { echo "Error: DDL file '$DDL_FILE' does not exist."; exit 1; }
[[ ! -d "$DATA_DIRECTORY" ]] && { echo "Error: Data directory '$DATA_DIRECTORY' does not exist."; exit 1; }
[[ ! "$NUM_FILES" =~ ^[0-9]+$ ]] && { echo "Error: NUM_FILES must be a positive integer."; exit 1; }

echo "Create database"
postgres_psql -d postgres -c "CREATE DATABASE \"$DB_NAME\""

echo "Execute DDL"
if postgres_psql -d postgres -Atqc \
    "CREATE TEMP TABLE jsonbench_lz4_probe(data text COMPRESSION lz4); DROP TABLE jsonbench_lz4_probe;" \
    >/dev/null 2>&1; then
    postgres_psql -d "$DB_NAME" -f "$DDL_FILE"
else
    if [[ "${PG_ALLOW_NO_LZ4:-0}" != "1" ]]; then
        echo "Error: PostgreSQL does not support lz4 compression required by '$DDL_FILE'." >&2
        echo "Use a PostgreSQL build with lz4 support, or set PG_ALLOW_NO_LZ4=1 for a non-comparable fallback run." >&2
        exit 1
    fi
    echo "Warning: lz4 is unavailable; running with table compression disabled (PG_ALLOW_NO_LZ4=1)." >&2
    sed -E 's/[[:space:]]+COMPRESSION[[:space:]]+lz4//g' "$DDL_FILE" | postgres_psql -d "$DB_NAME" -f -
fi

echo "Load data"
"$SCRIPT_DIR/load_data.sh" "$DATA_DIRECTORY" "$DB_NAME" "$TABLE_NAME" "$NUM_FILES" "$SUCCESS_LOG" "$ERROR_LOG"

echo "Vacuum analyze the table"
postgres_psql -d "$DB_NAME" -c "VACUUM ANALYZE \"$TABLE_NAME\""

loaded_rows=$(postgres_psql -d "$DB_NAME" -Atqc "SELECT count(*) FROM \"$TABLE_NAME\"")
if [[ ! "$loaded_rows" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: data load produced no rows in $DB_NAME.$TABLE_NAME (count='$loaded_rows')." >&2
    exit 1
fi
echo "Loaded rows: $loaded_rows"
