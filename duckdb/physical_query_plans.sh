#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DATABASE_NAME>"
    exit 1
fi

# Arguments
DATABASE_NAME="$1"
DB_PATH="$(duckdb_database_path "$DATABASE_NAME")"

QUERY_NUM=1

cat queries.sql | while read -r query; do

    # Print the query number
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "Physical query plan for query Q$QUERY_NUM:"
    echo

    duckdb "$DB_PATH" -c "EXPLAIN $query"

    # Increment the query number
    QUERY_NUM=$((QUERY_NUM + 1))
done;
