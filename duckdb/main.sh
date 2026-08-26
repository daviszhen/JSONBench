#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
export DUCKDB_DATA_DIR

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

# Dependencies are managed outside the benchmark runner.  JSONBench results
# use DuckDB 1.1.3 as their baseline, so prefer that versioned installation
# without installing or uninstalling DuckDB as a side effect of a run.
DEFAULT_DUCKDB_VERSION=1.1.3
DUCKDB_VERSION="${DUCKDB_VERSION:-$DEFAULT_DUCKDB_VERSION}"
DUCKDB_CLI_DIR="${DUCKDB_CLI_DIR:-$HOME/.duckdb/cli/$DUCKDB_VERSION}"

if [[ -x "$DUCKDB_CLI_DIR/duckdb" ]]; then
    export PATH="$DUCKDB_CLI_DIR:$PATH"
fi

if ! command -v duckdb >/dev/null 2>&1; then
    echo "Error: DuckDB $DUCKDB_VERSION was not found at '$DUCKDB_CLI_DIR/duckdb' or in PATH."
    echo "Install DuckDB before running this benchmark, or set DUCKDB_CLI_DIR to its installation directory."
    exit 1
fi
echo "Using $(duckdb --version) from $(command -v duckdb)"
echo "DuckDB database files: $DUCKDB_DATA_DIR"
mkdir -p "$DUCKDB_DATA_DIR"

benchmark() {
    local size=$1
    # Check DATA_DIRECTORY contains the required number of files to run the benchmark
    file_count=$(find "$DATA_DIRECTORY" -type f | wc -l)
    if (( file_count < size )); then
        echo "Error: Not enough files in '$DATA_DIRECTORY'. Required: $size, Found: $file_count."
        exit 1
    fi
    ./create_and_load.sh "db.duckdb_${size}" bluesky ddl.sql "$DATA_DIRECTORY" "$size" "$SUCCESS_LOG" "$ERROR_LOG"
    ./total_size.sh "db.duckdb_${size}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}m.data_size"
    ./count.sh "db.duckdb_${size}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}m.count"
    #./query_results.sh "db.duckdb_${size}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}m.query_results"
    ./physical_query_plans.sh "db.duckdb_${size}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}m.physical_query_plans"
    ./benchmark.sh "db.duckdb_${size}" "${OUTPUT_PREFIX}_bluesky_${size}m.results_runtime"
    ./drop_table.sh "db.duckdb_${size}"
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
