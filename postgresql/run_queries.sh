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

TRIES=3
QUERY_FILE="$SCRIPT_DIR/queries.sql"

if [[ ! -f "$QUERY_FILE" ]]; then
    echo "Error: query file '$QUERY_FILE' does not exist." >&2
    exit 1
fi

row_count=$(postgres_psql -d "$DB_NAME" -Atqc 'SELECT count(*) FROM bluesky')
if [[ ! "$row_count" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: refusing to benchmark '$DB_NAME': bluesky contains '$row_count' rows." >&2
    exit 1
fi

mapfile -t queries < <(awk 'NF { print }' "$QUERY_FILE")
if (( ${#queries[@]} != 5 )); then
    echo "Error: expected 5 benchmark queries in '$QUERY_FILE', found ${#queries[@]}." >&2
    exit 1
fi

for query in "${queries[@]}"; do

    # Clear the Linux file system cache
    echo "Clearing file system cache..."
    sync
    if [[ "${DROP_CACHES:-1}" == "1" ]]; then
        if [[ -w /proc/sys/vm/drop_caches ]]; then
            printf '3\n' > /proc/sys/vm/drop_caches
        elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
            printf '3\n' | sudo tee /proc/sys/vm/drop_caches >/dev/null
        else
            echo "Error: cannot clear the file system cache; set DROP_CACHES=0 only when a cold-cache run is not required." >&2
            exit 1
        fi
        echo "File system cache cleared."
    else
        echo "File system cache clearing disabled (DROP_CACHES=${DROP_CACHES:-0})."
    fi

    # Print the query
    echo "Running query: $query"

    # Execute the query multiple times
    for i in $(seq 1 $TRIES); do
        query_output=''
        if ! query_output=$(postgres_psql -d "$DB_NAME" -t -c '\timing' -c "$query" 2>&1); then
            echo "Error: query execution failed for '$query':" >&2
            printf '%s\n' "$query_output" >&2
            exit 1
        fi
        timing_line=$(printf '%s\n' "$query_output" | awk '/^Time:/ { line = $0 } END { if (line != "") print line }')
        if [[ -z "$timing_line" ]]; then
            echo "Error: query '$query' returned no timing." >&2
            printf '%s\n' "$query_output" >&2
            exit 1
        fi
        printf '%s\n' "$timing_line"
    done;
done
