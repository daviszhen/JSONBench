#!/bin/bash

set -Eeuo pipefail

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME> [RESULT_FILE]"
    exit 1
fi

# Arguments
DB_NAME="$1"
RESULT_FILE="${2:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
QUERY_LOG_FILE="${QUERY_LOG_FILE:-$SCRIPT_DIR/_query_log_${DB_NAME}.txt}"

# Print the database name
echo "Running queries on database: $DB_NAME"

# Run queries and log the output
if ! "$SCRIPT_DIR/run_queries.sh" "$DB_NAME" 2>&1 | tee "$QUERY_LOG_FILE"; then
    echo "Error: benchmark query execution failed for $DB_NAME; see $QUERY_LOG_FILE." >&2
    exit 1
fi

# Process the query log and prepare the result.  A complete run is exactly
# five queries x three timings; do not publish a partial or empty result.
timing_count=$(grep -c '^Time: ' "$QUERY_LOG_FILE" || true)
if [[ "$timing_count" -ne 15 ]]; then
    echo "Error: '$QUERY_LOG_FILE' contains $timing_count timings; expected 15." >&2
    exit 1
fi
RESULT=$(awk '/^Time: / {
    if ($3 != "ms") exit 1
    if (i % 3 == 0) printf "["
    printf "%s", $2 / 1000
    if (i % 3 != 2) printf ","; else print "],"
    i++
}' "$QUERY_LOG_FILE")

# Output the result
if [[ -n "$RESULT_FILE" ]]; then
    echo "$RESULT" > "$RESULT_FILE"
    echo "Result written to $RESULT_FILE"
else
    echo "$RESULT"
fi
