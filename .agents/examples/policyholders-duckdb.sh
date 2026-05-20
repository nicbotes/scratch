#!/usr/bin/env bash
# Demonstrates the pull-once-slice-many DuckDB pattern on the policyholders table.
#
# Why: Athena charges per byte scanned. DuckDB is free.
# Pattern: pay Athena once to pull a dataset to /tmp, then iterate over that
# local file with DuckDB as many times as needed — each slice is instant and free.
#
# Why CSV-to-/tmp and not Athena UNLOAD to Parquet?
# The Root Data Adapter IAM identity has no s3:PutObject permission (Athena
# writes query results on behalf of the user via the service principal —
# UNLOAD requires user-level S3 write, which isn't granted). So UNLOAD-based
# variants of this pattern are not runnable from a Data Adapter key. The
# athena-unload.sh / unload_prefix helpers exist for accounts that do have
# S3 write access (e.g. internal Root infra, or a customer's own AWS).
#
# Usage:
#   source .env && bash .agents/examples/policyholders-duckdb.sh
#
# Requirements: duckdb, aws CLI, env vars from .env

set -euo pipefail
AGENTS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$AGENTS_ROOT/tools/_lib.sh"
require_env

OUT=/tmp/policyholders_sample.csv

echo "==> Step 1: Pull policyholders from Athena (pay once)"
echo "    → writing to $OUT"
echo

bash "$AGENTS_ROOT/tools/athena-query.sh" --to-file "$OUT" "
  SELECT
    policyholder_id,
    type,
    title,
    gender,
    date_of_birth,
    identification_type,
    identification_country,
    city,
    country,
    area_code,
    created_at
  FROM policyholders
  WHERE environment = '${ROOT_ENV:-production}'
  LIMIT 10000
"

echo
echo "==> Step 2: Local DuckDB slices — Athena scan is paid for, these are free"
echo

# ---- 2a. individual vs company split ----------------------------------------
echo "--- policyholder type breakdown ---"
bash "$AGENTS_ROOT/tools/duckdb-query.sh" "
  SELECT
    type,
    COUNT(*) AS n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
  FROM '$OUT'
  GROUP BY type
  ORDER BY n DESC
"

echo

# ---- 2b. gender distribution (individuals only) ------------------------------
echo "--- gender distribution (individuals) ---"
bash "$AGENTS_ROOT/tools/duckdb-query.sh" "
  SELECT
    COALESCE(NULLIF(gender, ''), 'unknown') AS gender,
    COUNT(*) AS n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
  FROM '$OUT'
  WHERE type = 'individual'
  GROUP BY gender
  ORDER BY n DESC
"

echo

# ---- 2c. age buckets (from date_of_birth) ------------------------------------
echo "--- age distribution (individuals with a date_of_birth) ---"
bash "$AGENTS_ROOT/tools/duckdb-query.sh" "
  SELECT
    CASE
      WHEN age < 18  THEN '<18'
      WHEN age < 25  THEN '18-24'
      WHEN age < 35  THEN '25-34'
      WHEN age < 45  THEN '35-44'
      WHEN age < 55  THEN '45-54'
      WHEN age < 65  THEN '55-64'
      ELSE '65+'
    END AS age_bucket,
    COUNT(*) AS n
  FROM (
    SELECT
      DATE_DIFF('year', CAST(date_of_birth AS DATE), CURRENT_DATE) AS age
    FROM '$OUT'
    WHERE type = 'individual'
      AND date_of_birth IS NOT NULL
      AND CAST(date_of_birth AS VARCHAR) != ''
  )
  GROUP BY age_bucket
  ORDER BY
    CASE age_bucket
      WHEN '<18'   THEN 1 WHEN '18-24' THEN 2 WHEN '25-34' THEN 3
      WHEN '35-44' THEN 4 WHEN '45-54' THEN 5 WHEN '55-64' THEN 6
      ELSE 7
    END
"

echo

# ---- 2d. top cities ----------------------------------------------------------
echo "--- top 10 cities ---"
bash "$AGENTS_ROOT/tools/duckdb-query.sh" "
  SELECT
    COALESCE(NULLIF(TRIM(city), ''), 'unknown') AS city,
    COUNT(*) AS n
  FROM '$OUT'
  WHERE type = 'individual'
  GROUP BY city
  ORDER BY n DESC
  LIMIT 10
"

echo
echo "==> Done. All slices ran against $OUT — Athena was queried exactly once."
