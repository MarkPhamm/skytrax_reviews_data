#!/usr/bin/env bash
# Expand the CSVs stored as gzip because they exceed GitHub's 100 MB limit.
# The .gz files stay in place. Plain .csv files are written beside them so
# dbt can read data/raw/airline_reviews.csv.
#
# Usage:
#   ./decompress.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

files=(
    data/raw/airline_reviews.csv.gz
    data/airlines_reviews_model/fct_airline_review.csv.gz
)

cd "$REPO_ROOT"
for rel in "${files[@]}"; do
    if [[ ! -f "$rel" ]]; then
        echo "Missing $rel" >&2
        exit 1
    fi
    echo "Decompressing $rel"
    gzip -dfk "$rel"
done
