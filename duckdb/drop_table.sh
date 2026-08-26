#!/bin/bash 

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <database_name>"
    exit 1
fi

# Arguments
DATABASE_NAME="$1"
DB_PATH="$(duckdb_database_path "$DATABASE_NAME")"

echo "Dropping database: $DATABASE_NAME"

rm -f -- "$DB_PATH" "${DB_PATH}-c"
