#!/usr/bin/env bash
# scheduled-function-digest.sh — weekly hotspot digest for in-house devs
# tightening scheduled-function targeting at platform-managed orgs.
#
# Pulls rp_fact_scheduled_function_runs_view across ROOT_ORG_IDS for a 14-day
# window (current_week + prior_week), joins to rp_dim_product_view for product
# names, and writes a markdown digest under .agents/digests/<ISO-week>.md
# alongside a sibling manifest.json.
#
# Why this bypasses export-results.sh (rule #11): export-results is
# single-org by design. The digest is a cross-org aggregate; the manifest
# follows the same shape so downstream auditors get the same evidence
# pointer. The digest itself is aggregate-only (no PII), so the firewall
# in athena-query.sh + the view's own design are sufficient.
#
# Usage:
#   scheduled-function-digest.sh [--weeks-back N] [--window-days N]
#                                [--top-n N] [--lambda-rate USD/s]
#                                [--fargate-rate USD/s] [--out PATH]
#                                [--cleanup] [--explain]
#                                [--include-test-modules]
#
# See .agents/skills/digest-scheduled-functions.md for how to read the output.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

# This tool is genuinely multi-org; cross-org-pull.sh sets ROOT_ORG_ID per
# iteration internally. Set a sentinel here so _session_log and any other
# helpers that reference ROOT_ORG_ID under `set -u` don't blow up.
export ROOT_ORG_ID="${ROOT_ORG_ID:-cross-org}"

# ---- Defaults --------------------------------------------------------------

weeks_back=0
window_days=7
top_n=10
lambda_rate="0.0000167"     # AWS Lambda 1GB-sec
fargate_rate="0.0000010"    # AWS Fargate 1vCPU-sec (rough amortised)
out_path=""
cleanup=0
explain=0
include_test_modules=0

while (( $# )); do
  case "$1" in
    --weeks-back)            weeks_back="$2"; shift 2 ;;
    --window-days)           window_days="$2"; shift 2 ;;
    --top-n)                 top_n="$2"; shift 2 ;;
    --lambda-rate)           lambda_rate="$2"; shift 2 ;;
    --fargate-rate)          fargate_rate="$2"; shift 2 ;;
    --out)                   out_path="$2"; shift 2 ;;
    --cleanup)               cleanup=1; shift ;;
    --explain)               explain=1; shift ;;
    --include-test-modules)  include_test_modules=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) echo "unexpected positional arg: $1" >&2; exit 64 ;;
  esac
done

# ---- Window dates ----------------------------------------------------------
# date(1) on macOS (BSD) and Linux (GNU) have different flags. Use python3
# (always available — required for the framework's PII scan) for portability.
read -r current_end current_start prior_end prior_start iso_week <<<"$(
python3 - <<PY
import datetime as dt
weeks_back = $weeks_back
window_days = $window_days
today = dt.date.today()
current_end = today - dt.timedelta(days=weeks_back * window_days)
current_start = current_end - dt.timedelta(days=window_days)
prior_end = current_start
prior_start = prior_end - dt.timedelta(days=window_days)
iso_year, iso_week, _ = current_end.isocalendar()
print(current_end, current_start, prior_end, prior_start,
      f"{iso_year}-W{iso_week:02d}")
PY
)"

# ---- Output paths ----------------------------------------------------------

if [[ -z "$out_path" ]]; then
  out_path="$AGENTS_ROOT/digests/$iso_week.md"
fi
manifest_path="${out_path%.md}.manifest.json"
mkdir -p "$(dirname "$out_path")"

# Each cross-org-pull invocation creates its own .agents/cross-org/<ts>/
# workspace for CSVs. We give the .duckdb files a predictable home so the
# digest tool can find them and (optionally) clean up.
digest_ts="$(date -u +%Y%m%dT%H%M%SZ)"
workspace="$AGENTS_ROOT/cross-org/$digest_ts-digest"
mkdir -p "$workspace"
fact_this_db="$workspace/fact_this.duckdb"
fact_prior_db="$workspace/fact_prior.duckdb"
dim_db="$workspace/dim.duckdb"

# ---- SQL -------------------------------------------------------------------
#
# Two narrow pulls instead of one wide. The 14-day combined window blows
# bash's string-buffer in athena-query.sh for high-volume customer orgs (~5M rows / 1.4 GB CSV). 7-day per-pull is verified safe by the
# initial smoke test (2.3M rows / 700 MB).

fact_this_sql="SELECT * FROM rp_fact_scheduled_function_runs_view
WHERE started_at >= TIMESTAMP '${current_start} 00:00:00'
  AND started_at <  TIMESTAMP '${current_end} 00:00:00'"

fact_prior_sql="SELECT * FROM rp_fact_scheduled_function_runs_view
WHERE started_at >= TIMESTAMP '${prior_start} 00:00:00'
  AND started_at <  TIMESTAMP '${prior_end} 00:00:00'"

DIM_VIEW_NAME="rp_dim_product_view"

if (( explain )); then
  echo "# fact pull — current week (per org via cross-org-pull.sh)"
  echo "$fact_this_sql"
  echo
  echo "# fact pull — prior week (per org via cross-org-pull.sh)"
  echo "$fact_prior_sql"
  echo
  echo "# dim_product pull (per org via cross-org-pull.sh)"
  echo "SELECT * FROM $DIM_VIEW_NAME"
  echo
  echo "# windows:"
  echo "this_week:  $current_start .. $current_end"
  echo "prior_week: $prior_start .. $prior_end"
  echo
  echo "# outputs:"
  echo "digest:    $out_path"
  echo "manifest:  $manifest_path"
  echo "workspace: $workspace"
  exit 0
fi

if [[ -z "${ROOT_ORG_IDS:-}" ]]; then
  echo "error: ROOT_ORG_IDS unset. Source .agents/.env first." >&2
  exit 64
fi

t0=$(date +%s)

# ---- Pulls -----------------------------------------------------------------

echo "[digest] pulling fact (this week) for $current_start..$current_end across ROOT_ORG_IDS" >&2
fact_this_summary="$(bash "$AGENTS_ROOT/tools/cross-org-pull.sh" \
  --sql "$fact_this_sql" --out "$fact_this_db")"
echo "[digest] $fact_this_summary" >&2
fact_this_rows="$(printf '%s' "$fact_this_summary" | grep -oE 'rows=[0-9]+' | cut -d= -f2)"
fact_this_orgs="$(printf '%s' "$fact_this_summary" | grep -oE 'orgs=[0-9]+/[0-9]+')"

echo "[digest] pulling fact (prior week) for $prior_start..$prior_end across ROOT_ORG_IDS" >&2
fact_prior_summary="$(bash "$AGENTS_ROOT/tools/cross-org-pull.sh" \
  --sql "$fact_prior_sql" --out "$fact_prior_db")"
echo "[digest] $fact_prior_summary" >&2
fact_prior_rows="$(printf '%s' "$fact_prior_summary" | grep -oE 'rows=[0-9]+' | cut -d= -f2)"
fact_prior_orgs="$(printf '%s' "$fact_prior_summary" | grep -oE 'orgs=[0-9]+/[0-9]+')"

echo "[digest] pulling dim_product across ROOT_ORG_IDS" >&2
dim_summary="$(bash "$AGENTS_ROOT/tools/cross-org-pull.sh" \
  --view "$DIM_VIEW_NAME" --out "$dim_db")"
echo "[digest] $dim_summary" >&2
dim_rows="$(printf '%s' "$dim_summary" | grep -oE 'rows=[0-9]+' | cut -d= -f2)"

# ---- Test-module filter ----------------------------------------------------

if (( include_test_modules )); then
  test_filter=""
else
  # Filter on the COALESCE'd product_name (post-LEFT-JOIN) so rows where the
  # LEFT JOIN produced NULL (e.g. orgs without a dim_product view) survive — they get product_name = '<unknown>' which doesn't
  # match any test/sandbox patterns. The previous WHERE-on-d.product_name
  # form dropped NULL rows via three-valued logic.
  test_filter="AND COALESCE(d.product_name, '<unknown>') NOT LIKE '%[TESTING]%'
               AND COALESCE(d.product_name, '<unknown>') NOT LIKE '%[STAGING]%'
               AND COALESCE(d.product_name, '<unknown>') NOT LIKE '%playground%'
               AND COALESCE(d.product_name, '<unknown>') NOT LIKE '%Playground%'"
fi

# ---- Markdown sections -----------------------------------------------------
#
# Single duckdb invocation that ATTACHes both files, prints headers via
# .print, and emits markdown tables via .mode markdown. Cleaner than
# multiple invocations (one ATTACH cost) and gives the file a coherent shape.

now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

duckdb_script="$(mktemp -t digest-XXXXXX.sql)"
trap 'rm -f "$duckdb_script"' EXIT

cat > "$duckdb_script" <<DUCKDB
.mode markdown
.headers on

ATTACH '$fact_this_db'  AS fact_this  (READ_ONLY);
ATTACH '$fact_prior_db' AS fact_prior (READ_ONLY);
ATTACH '$dim_db'        AS dim_db     (READ_ONLY);

-- Joined view: fact (both weeks, UNIONed) ⋈ dim_product. NULL-safe LEFT JOIN
-- so unknown product_module_ids still appear (test orgs sometimes have rows
-- without a dim entry).
CREATE TEMP VIEW joined AS
WITH fact AS (
  SELECT *, 'this'  AS week_bucket FROM fact_this.unified
  UNION ALL
  SELECT *, 'prior' AS week_bucket FROM fact_prior.unified
)
SELECT
  f.org_id,
  f.org_name,
  f.product_module_id,
  COALESCE(d.product_name, '<unknown>') AS product_name,
  f.function_name,
  CASE WHEN f.function_name LIKE 'after%' OR f.function_name LIKE 'before%'
       THEN 'lifecycle' ELSE 'scheduled' END AS carve,
  f.duration_ms,
  f.started_at,
  f.completed_at,
  f.product_module_definition_id,
  f.week_bucket
FROM fact f
LEFT JOIN dim_db.unified d
  ON f.org_id = d.org_id
 AND f.product_module_id = d.product_module_id
WHERE 1=1
  ${test_filter};

-- ============ Summary =====================================================
.print
.print '## Summary'
.print

WITH wk AS (
  SELECT
    COUNT(*) AS runs,
    SUM(duration_ms) AS ms,
    COUNT(DISTINCT org_id) AS orgs,
    COUNT(DISTINCT function_name) AS funcs
  FROM joined WHERE week_bucket = 'this'
)
SELECT
  CAST(ROUND(ms / 3600000.0, 2) AS DOUBLE)           AS compute_h,
  CAST(ROUND(ms / 1000.0 * $lambda_rate, 2)  AS DOUBLE) AS lambda_usd,
  CAST(ROUND(ms / 1000.0 * $fargate_rate, 4) AS DOUBLE) AS fargate_usd,
  runs                                               AS total_runs,
  orgs                                               AS orgs,
  funcs                                              AS distinct_functions
FROM wk;

-- ============ Hotspots ====================================================
.print
.print '## Hotspots — top $top_n by compute spend (scheduled + lifecycle)'
.print
.print 'Rank by compute-hours. \`p99/p10\` is the bimodality proxy — high values suggest two populations (no-op cluster + real-work tail).'
.print

WITH agg AS (
  SELECT
    carve,
    org_name AS client,
    product_name AS product,
    function_name AS function,
    COUNT(*) AS runs,
    SUM(duration_ms) AS ms_sum,
    APPROX_QUANTILE(duration_ms, 0.10) AS p10,
    APPROX_QUANTILE(duration_ms, 0.50) AS p50,
    APPROX_QUANTILE(duration_ms, 0.99) AS p99
  FROM joined
  WHERE week_bucket = 'this'
  GROUP BY 1,2,3,4
)
SELECT
  ROW_NUMBER() OVER (ORDER BY ms_sum DESC NULLS LAST) AS rank,
  carve,
  client,
  product,
  function,
  runs,
  CAST(ROUND(ms_sum/3600000.0, 2) AS DOUBLE)             AS compute_h,
  CAST(ROUND(ms_sum/1000.0 * $lambda_rate, 2) AS DOUBLE) AS lambda_usd,
  CAST(ROUND(ms_sum/1000.0 * $fargate_rate, 4) AS DOUBLE) AS fargate_usd,
  CAST(p10 AS BIGINT) AS p10_ms,
  CAST(p50 AS BIGINT) AS p50_ms,
  CAST(p99 AS BIGINT) AS p99_ms,
  CAST(ROUND(CAST(p99 AS DOUBLE) / NULLIF(CAST(p10 AS DOUBLE), 0), 1) AS DOUBLE) AS p99_over_p10
FROM agg
ORDER BY ms_sum DESC NULLS LAST
LIMIT $top_n;

-- ============ Movers ======================================================
.print
.print '## Notable movers — biggest absolute compute-hour deltas'
.print
.print 'Deltas are this week − prior week. \`↻\` = the function ran under more than one \`product_module_definition_id\` this week — possible deploy artifact rather than a real targeting change.'
.print

WITH per_wk AS (
  SELECT
    org_name AS client,
    product_name AS product,
    function_name AS function,
    week_bucket,
    SUM(duration_ms) AS ms,
    COUNT(*) AS runs,
    COUNT(DISTINCT product_module_definition_id) AS defs
  FROM joined
  WHERE week_bucket IN ('this','prior')
  GROUP BY 1,2,3,4
), pivoted AS (
  SELECT
    client, product, function,
    SUM(CASE WHEN week_bucket='this'  THEN ms   ELSE 0 END) AS this_ms,
    SUM(CASE WHEN week_bucket='prior' THEN ms   ELSE 0 END) AS prior_ms,
    SUM(CASE WHEN week_bucket='this'  THEN runs ELSE 0 END) AS this_runs,
    SUM(CASE WHEN week_bucket='prior' THEN runs ELSE 0 END) AS prior_runs,
    MAX(CASE WHEN week_bucket='this'  THEN defs ELSE 0 END) AS this_defs
  FROM per_wk
  GROUP BY 1,2,3
)
SELECT
  CASE WHEN this_ms > prior_ms THEN '↑ up' ELSE '↓ down' END AS direction,
  CASE WHEN this_defs > 1 THEN function || ' ↻' ELSE function END AS function,
  product,
  client,
  this_runs,
  prior_runs,
  CAST(ROUND((this_ms - prior_ms) / 3600000.0, 2) AS DOUBLE) AS delta_h
FROM pivoted
WHERE prior_ms > 0 OR this_ms > 0
ORDER BY ABS(this_ms - prior_ms) DESC
LIMIT $top_n;

-- ============ Per-client rollup ===========================================
.print
.print '## Per-client rollup'
.print

WITH per_client AS (
  SELECT
    org_name AS client,
    COUNT(*) AS runs,
    SUM(duration_ms) AS ms
  FROM joined WHERE week_bucket = 'this'
  GROUP BY 1
), top_fn AS (
  SELECT
    org_name AS client,
    function_name AS top_function,
    SUM(duration_ms) AS ms,
    ROW_NUMBER() OVER (PARTITION BY org_name ORDER BY SUM(duration_ms) DESC NULLS LAST) AS rn
  FROM joined WHERE week_bucket = 'this'
  GROUP BY 1, 2
)
SELECT
  c.client,
  c.runs                                               AS total_runs,
  CAST(ROUND(c.ms/3600000.0, 2) AS DOUBLE)             AS compute_h,
  CAST(ROUND(c.ms/1000.0 * $lambda_rate,  2) AS DOUBLE) AS lambda_usd,
  CAST(ROUND(c.ms/1000.0 * $fargate_rate, 4) AS DOUBLE) AS fargate_usd,
  t.top_function
FROM per_client c
LEFT JOIN top_fn t ON c.client = t.client AND t.rn = 1
ORDER BY c.ms DESC NULLS LAST;

-- ============ NULL completed_at (crashes / still-running) =================
.print
.print '## NULL \`completed_at\` — crashes / still-running'
.print
.print 'Rows where \`completed_at\` is NULL — typically crashes or rows captured while still running. Separate signal from "did no work"; worth investigating per function.'
.print

WITH per_fn AS (
  SELECT
    org_name AS client,
    function_name AS function,
    SUM(CASE WHEN completed_at IS NULL THEN 1 ELSE 0 END) AS null_count,
    COUNT(*) AS total
  FROM joined WHERE week_bucket = 'this'
  GROUP BY 1, 2
)
SELECT
  client,
  function,
  null_count,
  total                                             AS total_runs,
  CAST(ROUND(100.0 * null_count / NULLIF(total, 0), 1) AS DOUBLE) AS pct_null
FROM per_fn
WHERE null_count > 0
ORDER BY null_count DESC
LIMIT $top_n;
DUCKDB

# Assemble the final markdown file
{
  cat <<EOF
# Scheduled function digest — $iso_week

_[single-source] As of $now_utc. Window: $current_start to $current_end (this week), $prior_start to $prior_end (prior). Cost basis: Lambda 1GB/s = \$$lambda_rate per compute-sec, Fargate 1vCPU = \$$fargate_rate per compute-sec. See [\`skills/digest-scheduled-functions.md\`](../skills/digest-scheduled-functions.md) for how to read this._

EOF

  duckdb -init /dev/null < "$duckdb_script"

  cat <<EOF

## Methodology

- **Hotspot rank** is by total \`compute-hours\` this week (\`SUM(duration_ms) / 3,600,000\`), not run count — a slow-but-rare function can outweigh a fast-but-frequent one.
- **\`p99/p10\` ratio** is the bimodality proxy. High ratio (≳10) → two populations: a fast cluster (likely no-ops) and a long tail (real work). Low ratio (≲3) → flat distribution; duration alone can't tell you whether everything's a no-op or everything's real work. The view doc (\`bi/fact_scheduled_function_runs_view.md\`) is explicit that \`duration_ms\` is a proxy, not ground truth — true no-op counts need product-module-side instrumentation.
- **Cost** is best-anchor not finance-accurate. Lambda 1GB/s (\$$lambda_rate/sec) and Fargate 1vCPU (\$$fargate_rate/sec) bracket the likely range; the ~20× spread itself is the useful signal ("matters a lot or barely at all depending on where this runs").
- **Movers** are ranked by absolute compute-hour delta, not percentage — a 10% jump on a 500-hour function matters more than a 200% jump on a 5-minute function. The \`↻\` glyph flags functions running under more than one \`product_module_definition_id\` this week; treat the delta with suspicion (it may be a deploy artifact, not a targeting-loop change).
- **Carve.** Scheduled-vs-lifecycle is named at query time by function-name prefix (\`after*\`/\`before*\` → lifecycle, everything else → scheduled). Convention drift can misclassify; scan the hotspots table for surprises and either rename in product code or special-case the carve. See \`bi/fact_scheduled_function_runs_view.md\` for the audit query.
- **Test/sandbox modules** are excluded (names containing \`[TESTING]\`, \`[STAGING]\`, \`playground\`). Override with \`--include-test-modules\`.
- **Workspace.** Each run writes intermediate DuckDB + CSVs into \`.agents/cross-org/<ts>-digest/\` and the parallel \`.agents/cross-org/<ts>/\` workspaces that \`cross-org-pull.sh\` creates per invocation. They persist across runs; clean up with \`scheduled-function-digest.sh --cleanup\` per-run, or periodically: \`find .agents/cross-org -mtime +90 -type d -exec rm -rf {} +\`.

→ Cross-references: [\`bi/fact_scheduled_function_runs_view.md\`](../bi/fact_scheduled_function_runs_view.md), [\`skills/ops-scheduled-function-volumes.md\`](../skills/ops-scheduled-function-volumes.md), [\`references/data-trust.md\`](../references/data-trust.md), [\`skills/digest-scheduled-functions.md\`](../skills/digest-scheduled-functions.md).
EOF
} > "$out_path"

# ---- Manifest --------------------------------------------------------------

t1=$(date +%s)
total_ms=$(( (t1 - t0) * 1000 ))

# Build orgs_included/orgs_skipped JSON arrays from the cross-org-pull summary.
# Format: orgs=N/T skipped=S. We don't have the per-org list in stdout; use
# what's in ROOT_ORG_IDS minus what the summary said was included/skipped.
orgs_arr="$(printf '%s' "${ROOT_ORG_IDS}" | python3 -c '
import json, sys
ids = [x.strip() for x in sys.stdin.read().split(",") if x.strip()]
print(json.dumps(ids))')"

escape_json() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'
}
fact_this_sql_json="$(printf '%s' "$fact_this_sql" | escape_json)"
fact_prior_sql_json="$(printf '%s' "$fact_prior_sql" | escape_json)"

cat > "$manifest_path" <<EOF
{
  "digest_week": "$iso_week",
  "generated_at": "$now_utc",
  "window_this_start": "$current_start",
  "window_this_end":   "$current_end",
  "window_prior_start": "$prior_start",
  "window_prior_end":   "$prior_end",
  "orgs_requested": $orgs_arr,
  "fact_pull_this": {
    "sql": $fact_this_sql_json,
    "rows": ${fact_this_rows:-0},
    "orgs_summary": "$fact_this_orgs",
    "out": "$fact_this_db"
  },
  "fact_pull_prior": {
    "sql": $fact_prior_sql_json,
    "rows": ${fact_prior_rows:-0},
    "orgs_summary": "$fact_prior_orgs",
    "out": "$fact_prior_db"
  },
  "dim_pull": {
    "view": "$DIM_VIEW_NAME",
    "rows": ${dim_rows:-0},
    "out": "$dim_db"
  },
  "cost_basis": {
    "lambda_usd_per_compute_sec":  $lambda_rate,
    "fargate_usd_per_compute_sec": $fargate_rate
  },
  "heuristic_version": "1",
  "test_modules_included": $( (( include_test_modules )) && echo true || echo false ),
  "wall_ms": $total_ms,
  "digest_path": "$out_path"
}
EOF

# ---- Cleanup ---------------------------------------------------------------

if (( cleanup )); then
  rm -rf "$workspace"
  echo "[digest] removed workspace $workspace" >&2
  echo "[digest] note: cross-org-pull.sh also created per-org CSVs in its own .agents/cross-org/<ts>/ workspace dirs — not cleaned up by this flag." >&2
fi

_session_log "scheduled-function-digest" "true" "$total_ms" "0"

echo "$out_path"
