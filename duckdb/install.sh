#!/bin/bash

rm -rf ~/.duckdb # remove remainders
DUCKDB_VERSION="${DUCKDB_VERSION:-1.1.3}"
curl https://install.duckdb.org | DUCKDB_VERSION="$DUCKDB_VERSION" sh
