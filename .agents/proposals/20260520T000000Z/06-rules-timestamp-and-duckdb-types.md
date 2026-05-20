# Proposal 06 — Rules: timestamp(3) literals, golden bounds, DuckDB type inference

**Source feedback notes (`feedback/2026-05-19.jsonl`):**
- `2026-05-19T14:03:13Z` (rule-missing) — Athena `timestamp(3)` columns cannot be compared with bare string literals; TYPE_MISMATCH error; use `date_format(col, '%Y-%m-%d') >= '2025-01-01'`
- `2026-05-19T14:14:53Z` (rule-missing) — regression goldens require both lower **and** upper bound; single-bound (`<` only) fails validation
- `2026-05-19T14:19:59Z` (rule-missing) — DuckDB auto-infers `TIMESTAMP` from CSV date columns; `SUBSTRING()` fails on TIMESTAMP type; use `CAST(col AS DATE)` instead of `STRPTIME(SUBSTRING(col,1,10),'%Y-%m-%d')`

## Reason

Three independent type-handling gotchas, each tripped at least one session this week. None is captured in `rules.md` or `references/examples.md` today; each costs ~5-15 minutes of debugging because the error message ("TYPE_MISMATCH") doesn't point at the fix.

Grouping them in one proposal because they're all "you assumed type X but the column is type Y, here's the cast" — same shape of mistake, same shape of fix.

## Current state

`rules.md` #3 says: "Dates are ISO 8601 strings. Wrap with `from_iso8601_timestamp(col)` before any arithmetic, comparison, or `AT TIME ZONE`. Do not `CAST` strings to dates."

This rule covers **varchar** date columns (stored as ISO strings). It does **not** cover the inverse: `timestamp(3)` columns (already typed) being compared against string literals. The Athena engine refuses to coerce — but the rule, as written, doesn't tell the agent which way around their column is.

`rules.md` #15 says goldens are time-bounded (`>=` and `<` both present, or `BETWEEN`). The validator enforces it; the rule states it. **No change** needed for the bound rule itself — but the validator's error message could be more helpful. (Out of scope for this proposal; flagged.)

`references/examples.md` does not document the DuckDB-on-CSV type inference gotcha.

## Proposed changes

### Change 1: extend `rules.md` #3 (cover both directions)

Replace:

```markdown
3. **Dates are ISO 8601 strings.** Wrap with `from_iso8601_timestamp(col)` before any arithmetic, comparison, or `AT TIME ZONE`. Do not `CAST` strings to dates.
```

With:

```markdown
3. **Date handling is type-directional.** Two patterns, depending on the column type:
   - **Varchar columns** (most `*_at` historical fields, all `policies.start_date`/`end_date`) store ISO 8601 strings. Wrap with `from_iso8601_timestamp(col)` before arithmetic, comparison, or `AT TIME ZONE`. Do not `CAST` strings to dates.
   - **`timestamp(3)` columns** (most `created_at`, `updated_at`) are already typed — comparing them against a bare string literal fails with `TYPE_MISMATCH`. Either compare against another timestamp (e.g. `from_iso8601_timestamp('2025-01-01')`) or coerce to string with `date_format(col, '%Y-%m-%d') >= '2025-01-01'`. The `date_format` form is the standard pattern for string-comparable date filtering in regression goldens.

   Check the column type in `references/schema.md` or via `glue-describe.sh <table>` before writing the predicate.
```

### Change 2: add `references/examples.md` entry — DuckDB CSV type inference

Append a new section (or insert near other DuckDB examples):

```markdown
## DuckDB on Athena CSV: dates auto-infer to TIMESTAMP

DuckDB's CSV reader inspects the first N rows and types ISO-shaped date columns as `TIMESTAMP`, not `VARCHAR`. Functions written assuming string input then fail:

```sql
-- ✗ Fails: SUBSTRING / STRPTIME expect VARCHAR
SELECT STRPTIME(SUBSTRING(created_at, 1, 10), '%Y-%m-%d') AS d
FROM read_csv_auto('/tmp/policies.csv');
-- Binder Error: No function matches the given name and argument types 'substring(TIMESTAMP, ...)'

-- ✓ Works: cast the inferred TIMESTAMP to DATE
SELECT CAST(created_at AS DATE) AS d
FROM read_csv_auto('/tmp/policies.csv');

-- ✓ Also works: bypass type inference, read as string, then parse
SELECT STRPTIME(SUBSTRING(created_at, 1, 10), '%Y-%m-%d') AS d
FROM read_csv_auto('/tmp/policies.csv', types={'created_at': 'VARCHAR'});
```

The first form is the right move 95% of the time — DuckDB inferred the type correctly; lean on it. The `types={...}` override exists for the edge case where the CSV column is intentionally non-ISO and you need to control parsing yourself.

Affects `skills/pre-aggregate.md` worked examples and `examples/policyholders-duckdb.sh`.
```

### Change 3: light touch on `rules.md` #15 (no rule change, footnote only)

The rule itself is correct. Add a clarifying note inside the existing entry:

```diff
 15. **Goldens are time-bounded and aggregate-shaped.** Every regression file pins a closed historical window (`>=` and `<` both present, or `BETWEEN`). Never `NOW()`, `CURRENT_DATE`, or "active today" — those drift legitimately and produce noise. Golden SQL produces aggregates (counts, sums, percentiles, group-bys) so the committed `result` field is innocuous — row-level captures belong in `export-results.sh` evidence (`.agents/evidence/`, gitignored), **never** in regressions.
+
+    Standard pattern for an all-history golden: `WHERE date_format(created_at, '%Y-%m-%d') >= '2010-01-01' AND date_format(created_at, '%Y-%m-%d') < '<next-year>'`. The validator in `regression-record.sh` rejects single-bound windows; this is intentional, not a bug.
```

## Test

Apply, then exercise each gotcha:

```bash
# timestamp(3) literal comparison
bash .agents/tools/athena-query.sh \
  "SELECT COUNT(*) FROM policies WHERE date_format(created_at, '%Y-%m-%d') >= '2025-01-01' AND date_format(created_at, '%Y-%m-%d') < '2026-01-01'"
# should succeed

# DuckDB CSV date handling (using the existing example script)
bash .agents/examples/policyholders-duckdb.sh
# should run end-to-end without STRPTIME/SUBSTRING errors

# Golden validation (rejects single-bound)
bash .agents/tools/regression-record.sh test_single_bound \
  "SELECT COUNT(*) FROM policies WHERE date_format(created_at, '%Y-%m-%d') < '2026-01-01'"
# should refuse with a message pointing at rules.md #15
```

Acceptance: rules.md gives the right answer to "should I cast or not?" on first read for both directions; examples.md prevents the DuckDB-CSV gotcha from re-occurring.
