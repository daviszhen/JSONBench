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

echo "Dropping database"
postgres_psql -d postgres -c "DROP DATABASE \"$DB_NAME\""
