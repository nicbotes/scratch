---
name: explore-schema
description: Discover Athena tables and columns before writing SQL. Use when you need to confirm a table/column exists, when a query failed with "column not found", or when the user mentions a table not in references/schema.md. Do NOT use when the table is already in references/schema.md and you don't need new columns.
---

# Skill: explore-schema

Schema reconnaissance. Cheap to run — the agent should reach for this before guessing a column name.

## Steps

1. List tables:
   ```bash
   bash .agents/tools/athena-describe.sh
   ```
2. Pick the table(s) relevant to the question. Cross-check against `references/schema.md` — if the table is there with the columns you need, stop.
3. Describe a specific table:
   ```bash
   bash .agents/tools/athena-describe.sh policies
   ```
4. Sample a few rows to see real values (JSON columns especially):
   ```bash
   bash .agents/tools/athena-query.sh "SELECT * FROM policies WHERE environment='$ROOT_ENV' LIMIT 5"
   ```
5. If the table is genuinely missing from `references/schema.md`, call `observe` with `--kind reference-thrash` so the reference gets updated next retro.

## Reference

JSON-typed columns (`module`, `charges`, `policy_events.data`) show as `varchar` in `DESCRIBE`. Sample rows to see their shape, then use `JSON_EXTRACT_SCALAR` to query them (see `references/athena-sql.md`).

→ Next: `run-query`, `profile-data`, or `analyst-workflow`.
