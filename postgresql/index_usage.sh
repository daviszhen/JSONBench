#!/bin/bash

set -Eeuo pipefail

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh" || exit 1

QUERY_NUM=1
while IFS= read -r query; do
    [[ -z "$query" ]] && continue

    # Print the query number
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "Index usage for query Q$QUERY_NUM:"
    echo

    postgres_psql -d "$DB_NAME" -c "EXPLAIN $query"

    # Increment the query number
    QUERY_NUM=$((QUERY_NUM + 1))

done < "$SCRIPT_DIR/queries.sql"
