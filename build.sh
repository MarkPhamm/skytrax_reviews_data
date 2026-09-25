#!/usr/bin/env bash
# Build the four Skytrax star schemas with dbt + DuckDB and export each one as
# CSVs under data/<subject>_reviews_model/.
#
# Usage:
#   ./build.sh                 # build everything
#   ./build.sh --full-refresh  # rebuild the incremental facts from scratch
#   ./build.sh -s lounge_reviews   # any dbt selector is passed straight through
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$REPO_ROOT/.venv/bin/python}"
DBT_BIN="${DBT_BIN:-$REPO_ROOT/.venv/bin/dbt}"

export SKYTRAX_RAW_DIR="${SKYTRAX_RAW_DIR:-$REPO_ROOT/data/raw}"
export SKYTRAX_EXPORT_ROOT="${SKYTRAX_EXPORT_ROOT:-$REPO_ROOT/data}"
export SKYTRAX_DUCKDB_PATH="${SKYTRAX_DUCKDB_PATH:-$REPO_ROOT/skytrax_reviews.duckdb}"
export DBT_PROFILES_DIR="$REPO_ROOT/dbt"

if [[ ! -x "$DBT_BIN" ]]; then
    echo "dbt not found at $DBT_BIN - run: $PYTHON_BIN -m pip install -r requirements.txt" >&2
    exit 1
fi

# DuckDB's COPY will not create missing directories, so make the export targets
# up front. One directory per star schema.
for model_dir in airlines_reviews_model airport_reviews_model lounge_reviews_model seat_reviews_model; do
    mkdir -p "$SKYTRAX_EXPORT_ROOT/$model_dir"
done

cd "$REPO_ROOT/dbt"
"$DBT_BIN" deps
"$DBT_BIN" build "$@"

echo
echo "Star schemas exported to:"
for model_dir in airlines_reviews_model airport_reviews_model lounge_reviews_model seat_reviews_model; do
    echo "  $SKYTRAX_EXPORT_ROOT/$model_dir"
done
