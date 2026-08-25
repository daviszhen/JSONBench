#!/bin/bash

set -Eeuo pipefail

# Check if the required arguments are provided
if [[ $# -lt 6 ]]; then
    echo "Usage: $0 <directory> <database_name> <table_name> <max_files> <success_log> <error_log>"
    exit 1
fi

# Arguments
DIRECTORY="$1"
DB_NAME="$2"
TABLE_NAME="$3"
MAX_FILES="$4"
SUCCESS_LOG="$5"
ERROR_LOG="$6"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh" || exit 1

# Validate that MAX_FILES is a number
if ! [[ "$MAX_FILES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: <max_files> must be a positive integer."
    exit 1
fi

# Ensure the log files exist
touch "$SUCCESS_LOG" "$ERROR_LOG"

# Create a temporary directory in /var/tmp and ensure it's accessible
TEMP_DIR=$(mktemp -d /var/tmp/cleaned_files.XXXXXX)
chmod 777 "$TEMP_DIR"  # Allow access for all users
trap "rm -rf $TEMP_DIR" EXIT  # Ensure cleanup on script exit

# Counter to track processed files
counter=0
successful_files=0
failed_files=0
loaded_rows=0

shopt -s nullglob
files=("$DIRECTORY"/*.json.gz)
if (( ${#files[@]} == 0 )); then
    echo "Error: no .json.gz files found in '$DIRECTORY'." >&2
    exit 1
fi
mapfile -t files < <(printf '%s\n' "${files[@]}" | sort)

# Loop through each .json.gz file in the directory
for file in "${files[@]}"; do
    # The limit is on attempted input files, not only successful imports.
    # Keep this guard before any operation that can continue on an error;
    # otherwise a failed file would bypass the old trailing break and a
    # 1m run could unexpectedly consume the entire directory.
    if (( counter >= MAX_FILES )); then
        break
    fi
    if [[ -f "$file" ]]; then
        echo "Processing $file..."
        counter=$((counter + 1))

        # Uncompress the file into the temporary directory
        uncompressed_file="$TEMP_DIR/$(basename "${file%.gz}")"
        if ! gunzip -c "$file" > "$uncompressed_file"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to uncompress $file." >> "$ERROR_LOG"
            failed_files=$((failed_files + 1))
            continue
        fi

        # Preprocess the file to remove null characters
        cleaned_file="$TEMP_DIR/$(basename "${uncompressed_file%.json}_cleaned.json")"
        if ! sed 's/\\u0000//g' "$uncompressed_file" > "$cleaned_file"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to preprocess $file." >> "$ERROR_LOG"
            failed_files=$((failed_files + 1))
            continue
        fi

        # Grant read permissions for the postgres user
        chmod 644 "$cleaned_file"

        # Import the cleaned JSON file into PostgreSQL
        copy_output=''
        if copy_output=$(postgres_psql -d "$DB_NAME" -c "\COPY $TABLE_NAME FROM '$cleaned_file' WITH (format csv, quote e'\x01', delimiter e'\x02', escape e'\x01');" 2>&1); then
            if [[ "$copy_output" =~ COPY[[:space:]]+([0-9]+) ]]; then
                file_rows="${BASH_REMATCH[1]}"
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] COPY returned no row count for $cleaned_file: $copy_output" >> "$ERROR_LOG"
                failed_files=$((failed_files + 1))
                continue
            fi
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to import $cleaned_file: $copy_output" >> "$ERROR_LOG"
            failed_files=$((failed_files + 1))
            continue
        fi

        if [[ "$file_rows" =~ ^[1-9][0-9]*$ ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Successfully imported $cleaned_file into PostgreSQL." >> "$SUCCESS_LOG"
            successful_files=$((successful_files + 1))
            loaded_rows=$((loaded_rows + file_rows))
            # Delete both the uncompressed and cleaned files after successful processing
            rm -f "$uncompressed_file" "$cleaned_file"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] COPY imported no rows from $cleaned_file." >> "$ERROR_LOG"
            failed_files=$((failed_files + 1))
            # Keep the files for debugging purposes
        fi

    else
        echo "No .json.gz files found in the directory."
    fi
done

if (( counter >= MAX_FILES )); then
    echo "Processed maximum number of files: $MAX_FILES"
fi

echo "Files processed: $counter; successful: $successful_files; failed: $failed_files; rows loaded: $loaded_rows"
if (( loaded_rows == 0 )); then
    echo "Error: no rows were loaded into $DB_NAME.$TABLE_NAME." >&2
    exit 1
fi
