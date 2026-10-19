#!/usr/bin/env bash
# Regenerate the ERD schema files under erd/ from the dbt project, using qdbd
# (quickdbd-cli). Only needs `dbt parse`, so no data or warehouse is required.
#
# Usage:
#   ./erd.sh            # refresh erd/*.txt and build erd/index.html
#   ./erd.sh --serve    # also open the live editor to drag tables around
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DBT_BIN="${DBT_BIN:-$REPO_ROOT/.venv/bin/dbt}"
QDBD_BIN="${QDBD_BIN:-qdbd}"
ERD_DIR="$REPO_ROOT/erd"

export SKYTRAX_DUCKDB_PATH="${SKYTRAX_DUCKDB_PATH:-$REPO_ROOT/skytrax_reviews.duckdb}"
export DBT_PROFILES_DIR="$REPO_ROOT/dbt"

if [[ ! -x "$DBT_BIN" ]]; then
    echo "dbt not found at $DBT_BIN - run: python -m pip install -r requirements.txt" >&2
    exit 1
fi
if ! command -v "$QDBD_BIN" >/dev/null; then
    echo "qdbd not found - run: python -m pip install quickdbd-cli" >&2
    exit 1
fi

(cd "$REPO_ROOT/dbt" && "$DBT_BIN" deps --quiet && "$DBT_BIN" parse --quiet)

# Marts only: the dims and facts people query. Staging and intermediate carry
# almost no relationships, and their lineage is what dbt docs is for.
# The import overwrites the .txt files; table positions in qdbd.layout.json survive.
"$QDBD_BIN" import dbt "$REPO_ROOT/dbt/target/manifest.json" \
    --select 'models/marts/*' --no-sources -o "$ERD_DIR/"
"$QDBD_BIN" check --strict "$ERD_DIR/" "$REPO_ROOT/data_model/schema.txt"
if [[ ! -f "$ERD_DIR/qdbd.layout.json" ]]; then
    "$QDBD_BIN" layout "$ERD_DIR/" --by-group
fi
"$QDBD_BIN" build "$ERD_DIR/" -o "$ERD_DIR/index.html"

if [[ "${1:-}" == "--serve" ]]; then
    "$QDBD_BIN" serve "$ERD_DIR/"
fi
