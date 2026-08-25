#!/bin/bash 

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Check if the required arguments are provided
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <database_name> <table_name>"
    exit 1
fi

# Arguments
DATABASE_NAME="$1"
TABLE_NAME="$2"
DB_PATH="$(duckdb_database_path "$DATABASE_NAME")"

# Fetch the count using duckDB
duckdb "$DB_PATH" -c "select count() from '$TABLE_NAME';"
