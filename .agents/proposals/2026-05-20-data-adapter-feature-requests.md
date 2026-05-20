# Data Adapter feature requests — retro notes

Logged 2026-05-20 from a session trying to migrate `examples/policyholders-duckdb.sh` from `athena-query.sh --to-file` CSV to Athena UNLOAD → Parquet. Two distinct platform asks surfaced. Both block real workflows that the current toolchain otherwise advertises as supported.

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

## Notes / non-asks

- The `unload_prefix()` patch landed this session is independently correct and worth keeping even before the IAM grant — accounts that *do* have S3 write capability (internal Root infra, customer-own AWS) can use UNLOAD today via this path.
- The workgroup naming convention (`<org-id>` as both workgroup name and database name) was easy to reverse-engineer from `aws athena list-work-groups`; no ask there.
- See [[project-athena-unload-no-iam-write]] memory for the IAM context referenced above.
