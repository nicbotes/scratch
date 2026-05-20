# Data Adapter feature requests — retro notes

Logged 2026-05-20 from a session trying to migrate `examples/policyholders-duckdb.sh` from `athena-query.sh --to-file` CSV to Athena UNLOAD → Parquet. Three distinct platform asks surfaced. Each blocks or taxes a real workflow that the current toolchain otherwise advertises as supported.

---

## 1. Grant `s3:PutObject` on a scoped prefix (unblocks Athena UNLOAD)

**Ask.** Extend the Root Data Adapter IAM policy (the one attached to the `AthenaUsers/<org-id>` user that the Data Adapter access key authenticates as) to allow `s3:PutObject` on a scoped UNLOAD prefix — e.g. `s3://root-data-adapter-production/organizations/<org>/unloads/*`.

**Why this matters.** Athena UNLOAD is the standard way to produce typed, columnar exports of a query for downstream tooling (DuckDB, Spark, dbt, BI). Right now UNLOAD fails for any Data Adapter key with `PERMISSION_DENIED: ... no identity-based policy allows the s3:PutObject action`, regardless of which prefix is targeted. This is because normal Athena queries write results via the Athena service principal (bypassing user IAM), while UNLOAD executes the `TO 's3://...'` clause under user credentials — which currently has zero S3 write capability. `EnforceWorkGroupConfiguration=true` on the workgroup redirects normal results but does not rewrite UNLOAD destinations.

**Impact.** The whole "pull once, slice many in DuckDB" pattern is currently limited to CSV-to-`/tmp` (single shell, single session). With UNLOAD enabled we get:
- Typed columns (no string→date casting hacks downstream).
- Snappy-compressed Parquet (smaller transfers, faster column-projected scans).
- A stable, shareable S3 artefact that survives sessions and is BI-tool ready.

`.agents/tools/athena-unload.sh` exists and was patched in this session (`unload_prefix()` in `_lib.sh` now derives the prefix from the workgroup's `ResultConfiguration.OutputLocation`), but is still unusable without the IAM grant. See [[../examples/policyholders-duckdb.sh]] header comment for the current workaround note.

**Scope suggestion.** Permission should be scoped to the workgroup's existing prefix (one already exists per org). A `unloads/` subprefix is a reasonable carve-out — keeps unload artefacts separate from query-result CSVs.

---

## 2. Reliable row count for `--to-file` / large result sets

**Ask.** Expose a row count for Athena queries whose result CSV is downloaded directly from S3 (not paginated via `GetQueryResults`). Today `aws athena get-query-execution` returns `Statistics.OutputRows = None` for these queries, which makes our `athena-query.sh --to-file` report `rows=0` for non-empty results.

**Concrete example from this session.** `athena-query.sh --to-file /tmp/policyholders_sample.csv ...` printed:

```
/tmp/policyholders_sample.csv rows=0 bytes=21167 s3_uri=s3://...
```

…but the file actually contained 154 rows and the downstream DuckDB slices ran fine. The stat lies; everything else works.

**Why this matters.** Row count is one of the few cheap signals an agent has to decide whether to apply the row cap, ask for confirmation, or page through results. Defaulting to 0 either suppresses the cap (sometimes silently flooding context with 100k rows) or trips defensive code paths that abort on apparent emptiness. Both are wrong.

**Options for the Data Adapter team.**
- Surface row counts in a separate field (e.g. via a Data Adapter metadata endpoint or an extension of `Statistics`).
- Document the `OutputRows=None` behaviour and the conditions that trigger it, so wrapping tooling can confidently compute rows post-hoc (e.g. `wc -l` minus header on the downloaded file).
- If neither is feasible: a note in the Data Adapter docs alongside the OutputLocation reference, so future tool authors don't trust the value.

**Where it bites in our code.** `tools/athena-query.sh:131` includes `rows=$total_rows` in the `--to-file` locator output; `total_rows` comes from `LAST_QUERY_ROWS` populated by `run_athena` in `tools/_lib.sh:138`, which reads `Statistics.OutputRows` and normalises `None → 0`. Either we patch every consumer to fall back to `wc -l` (workable but smelly), or we get an upstream fix.

---

## 3. Preserve column types in default query results

**Ask.** Make declared column types survive Athena's default query-result CSV path — either by switching the default workgroup result format to Parquet, by emitting a sidecar schema JSON alongside the CSV, or at minimum by documenting the erasure so wrapping tooling can attach `column_types=...` hints. Today every downstream consumer must repeat `CAST(col AS <real-type>)` rituals for columns that are *already* correctly typed upstream.

**Concrete example from this session.** `policyholders.date_of_birth` is declared `timestamp(3)` in the Glue catalog (`references/schema.md:84`). When `examples/policyholders-duckdb.sh` pulls it via `athena-query.sh --to-file` and queries it with DuckDB, DuckDB's CSV reader infers TIMESTAMP from the value pattern (`1995-03-12 00:00:00.000`) — well enough to break the original `SUBSTRING()/STRPTIME()` chain that assumed VARCHAR. The fix landed at `examples/policyholders-duckdb.sh:99-103`:

```sql
DATE_DIFF('year', CAST(date_of_birth AS DATE), CURRENT_DATE) AS age
FROM '$OUT'
WHERE type = 'individual'
  AND date_of_birth IS NOT NULL
  AND CAST(date_of_birth AS VARCHAR) != ''
```

Both casts disappear if the column arrives in DuckDB with its declared type.

**Why this matters.** The ergonomics tax compounds. Every downstream script repeats variants of the cast; `rules.md:9` (rule #3 — "Dates are ISO 8601 strings. Wrap with `from_iso8601_timestamp(col)` before arithmetic. Do not CAST strings to dates.") is itself a workaround for type loss — and contradicts what DuckDB needs (CAST). Different consumers need different incantations for the same underlying data. Type-aware export collapses all of that.

**Options for the Data Adapter team.**
- Make Parquet the default workgroup result format. Preserves types end-to-end, no UNLOAD required, works for read-only IAM identities. Cleanest fix, biggest blast radius.
- Emit a sidecar `<query-id>.schema.json` alongside the CSV (Athena CTAS already produces one for materialised tables). Downstream tools opt-in to read it.
- Document the erasure explicitly so wrappers can attach `column_types=...` hints to their CSV readers.

**Related: schema-declaration drift.** While auditing this, six columns surfaced that hold date/timestamp data but are declared `varchar` in the Glue catalog — they'd still need casts even *with* a typed default-result fix:

- `users.date_of_birth`, `users.last_logged_in`, `users.password_last_changed` (`references/schema.md:651,661-662`; the last two already carry inline annotations like "timestamp with tz stored as varchar; cast before arithmetic").
- `leads.identification_expiration_date`, `leads.date_of_birth` (`references/schema.md:946-947`).
- `members.date_of_birth` (`references/schema.md:193`).

Contrast `policyholders.identification_expiration_date` at `references/schema.md:88`, which IS declared `timestamp(3)` — so the catalog already has the right precedent; the varchar declarations on the other six are a drift to clean up, not a redesign. A smaller, independent ask the Data Adapter team can land without coordinating workgroup config changes.

**Cross-reference.** This ask partially overlaps with #1 (s3:PutObject). Granting s3:PutObject unlocks Athena UNLOAD-to-Parquet which preserves types — solving the cast problem for accounts that *write* their outputs. A typed default result remains the only path for *read-only* Data Adapter users (the common case). The two asks are complementary, not duplicates.

---

## Notes / non-asks

- The `unload_prefix()` patch landed this session is independently correct and worth keeping even before the IAM grant — accounts that *do* have S3 write capability (internal Root infra, customer-own AWS) can use UNLOAD today via this path.
- The workgroup naming convention (`<org-id>` as both workgroup name and database name) was easy to reverse-engineer from `aws athena list-work-groups`; no ask there.
- See [[project-athena-unload-no-iam-write]] memory for the IAM context referenced above.
