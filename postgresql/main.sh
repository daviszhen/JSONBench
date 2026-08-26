#!/bin/bash

set -Eeuo pipefail

DEFAULT_CHOICE=ask
DEFAULT_DATA_DIRECTORY=~/data/bluesky

# Allow the user to optionally provide the scale factor ("choice") as an argument
CHOICE="${1:-$DEFAULT_CHOICE}"

# Allow the user to optionally provide the data directory as an argument
DATA_DIRECTORY="${2:-$DEFAULT_DATA_DIRECTORY}"

# Define success and error log files
SUCCESS_LOG="${3:-success.log}"
ERROR_LOG="${4:-error.log}"

# Define prefix for output files
OUTPUT_PREFIX="${5:-_m6i.8xlarge}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh" || exit 1

# Check if the directory exists
if [[ ! -d "$DATA_DIRECTORY" ]]; then
    echo "Error: Data directory '$DATA_DIRECTORY' does not exist."
    exit 1
fi

if [ "$CHOICE" = "ask" ]; then
    echo "Select the dataset size to benchmark:"
    echo "1) 1m (default)"
    echo "2) 10m"
    echo "3) 100m"
    echo "4) 1000m"
    echo "5) all"
    read -p "Enter the number corresponding to your choice: " CHOICE
fi

# Dependencies are managed outside the benchmark runner.  Require an
# available PostgreSQL client and server instead of installing or removing
# PostgreSQL as a side effect of running the benchmark.
if ! postgres_psql -d postgres -Atqc 'SELECT 1' >/dev/null 2>&1; then
    echo "Error: PostgreSQL server is not available through the postgres user." >&2
    echo "Set PGHOST/PGPORT (and PG_BIN when needed) to the intended instance." >&2
    exit 1
fi

if ! SERVER_INFO=$(postgres_server_info); then
    echo "Error: unable to identify the PostgreSQL instance used by the benchmark." >&2
    exit 1
fi
printf 'PostgreSQL instance (version/data_directory/port/address):\n%s\n' "$SERVER_INFO"

# PGDATA controls server-side tools such as pg_ctl; it does not control which
# instance psql connects to.  When PGDATA is supplied, reject a mismatched
# endpoint instead of silently benchmarking another cluster.
if [[ -n "${PGDATA:-}" ]]; then
    if [[ ! -d "$PGDATA" ]]; then
        echo "Error: PGDATA '$PGDATA' does not exist or is not a directory." >&2
        exit 1
    fi
    EXPECTED_DATA_DIRECTORY=$(readlink -f -- "$PGDATA" 2>/dev/null || true)
    ACTUAL_DATA_DIRECTORY=$(postgres_psql -d postgres -Atqc "SELECT COALESCE(NULLIF(current_setting('data_directory', true), ''), '')")
    ACTUAL_DATA_DIRECTORY=$(readlink -f -- "$ACTUAL_DATA_DIRECTORY" 2>/dev/null || printf '%s' "$ACTUAL_DATA_DIRECTORY")
    if [[ -z "$ACTUAL_DATA_DIRECTORY" ]]; then
        echo "Warning: connected PostgreSQL did not expose data_directory; cannot verify PGDATA '$EXPECTED_DATA_DIRECTORY'." >&2
    elif [[ -n "$EXPECTED_DATA_DIRECTORY" && "$EXPECTED_DATA_DIRECTORY" != "$ACTUAL_DATA_DIRECTORY" ]]; then
        echo "Error: PGDATA '$EXPECTED_DATA_DIRECTORY' does not match the connected PostgreSQL data directory '$ACTUAL_DATA_DIRECTORY'." >&2
        echo "Set PGHOST/PGPORT to the intended PostgreSQL instance before running the benchmark." >&2
        exit 1
    fi
fi

validate_positive_metric() {
    local file="$1"
    local name="$2"
    local value

    if [[ ! -s "$file" ]]; then
        echo "Error: $name output '$file' is empty." >&2
        return 1
    fi
    value=$(tr -d '[:space:]' < "$file")
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: $name output '$file' is not a positive integer: '$value'." >&2
        return 1
    fi
}

validate_runtime_metric() {
    local file="$1"
    local timing_count

    if [[ ! -s "$file" ]]; then
        echo "Error: query runtime output '$file' is empty." >&2
        return 1
    fi
    timing_count=$(grep -oE '[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?' "$file" | wc -l)
    if [[ "$timing_count" -ne 15 ]]; then
        echo "Error: query runtime output '$file' contains $timing_count values; expected 15 (5 queries x 3 runs)." >&2
        return 1
    fi
}

benchmark() {
    local size=$1
    local db_name="bluesky_${size}m"
    local count_file="${OUTPUT_PREFIX}_bluesky_${size}m.count"
    local total_size_file="${OUTPUT_PREFIX}_bluesky_${size}m.total_size"
    local data_size_file="${OUTPUT_PREFIX}_bluesky_${size}m.data_size"
    local index_size_file="${OUTPUT_PREFIX}_bluesky_${size}m.index_size"
    local index_usage_file="${OUTPUT_PREFIX}_bluesky_${size}m.index_usage"
    local runtime_file="${OUTPUT_PREFIX}_bluesky_${size}m.results_runtime"

    # Check DATA_DIRECTORY contains the required number of files to run the benchmark
    file_count=$(find "$DATA_DIRECTORY" -type f -name '*.json.gz' | wc -l)
    if (( file_count < size )); then
        echo "Error: Not enough files in '$DATA_DIRECTORY'. Required: $size, Found: $file_count."
        exit 1
    fi

    if ! "$SCRIPT_DIR/create_and_load.sh" "$db_name" bluesky "$SCRIPT_DIR/ddl.sql" \
        "$DATA_DIRECTORY" "$size" "$SUCCESS_LOG" "$ERROR_LOG"; then
        echo "Error: database creation or data loading failed for $db_name; keeping it for debugging." >&2
        return 1
    fi
    if ! "$SCRIPT_DIR/total_size.sh" "$db_name" bluesky | tee "$total_size_file"; then
        return 1
    fi
    if ! "$SCRIPT_DIR/data_size.sh" "$db_name" bluesky | tee "$data_size_file"; then
        return 1
    fi
    if ! "$SCRIPT_DIR/index_size.sh" "$db_name" | tee "$index_size_file"; then
        return 1
    fi
    if ! "$SCRIPT_DIR/count.sh" "$db_name" bluesky | tee "$count_file"; then
        return 1
    fi
    validate_positive_metric "$count_file" "row count" || return 1
    validate_positive_metric "$total_size_file" "total size" || return 1
    validate_positive_metric "$data_size_file" "data size" || return 1
    validate_positive_metric "$index_size_file" "index size" || return 1

    if ! "$SCRIPT_DIR/index_usage.sh" "$db_name" | tee "$index_usage_file"; then
        return 1
    fi
    if ! grep -q 'Index usage for query Q5:' "$index_usage_file"; then
        echo "Error: index usage output '$index_usage_file' is incomplete." >&2
        return 1
    fi

    if ! "$SCRIPT_DIR/benchmark.sh" "$db_name" "$runtime_file"; then
        return 1
    fi
    validate_runtime_metric "$runtime_file" || return 1

    if ! "$SCRIPT_DIR/drop_tables.sh" "$db_name"; then
        echo "Error: failed to drop benchmark database $db_name." >&2
        return 1
    fi
}

case $CHOICE in
    2)
        benchmark 10
        ;;
    3)
        benchmark 100
        ;;
    4)
        benchmark 1000
        ;;
    5)
        benchmark 1
        benchmark 10
        benchmark 100
        benchmark 1000
        ;;
    *)
        benchmark 1
        ;;
esac
