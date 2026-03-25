# /rp-generate — Generate Schemas and API Documentation

Generate JSON schemas, API payloads, and documentation from the Joi validation in the product module code.

## Arguments

`$ARGUMENTS` may specify a workflow step: `quote`, `application`, or `alterations`.
If no step is specified, generate for all steps.

## Steps

1. **Determine scope**
   Check `$ARGUMENTS`:
   - If it contains `quote`, `application`, or `alterations` → run with that specific step
   - If empty → run without a `--workflow` flag (generates all)

2. **Run generate**

   With a specific step:
   ```bash
   rp generate --workflow $ARGUMENTS
   ```
   Without a specific step:
   ```bash
   rp generate
   ```

3. **Show outputs**
   After generation, list the files created/updated in:
   - `./sandbox/` — schemas and API documentation
   - `./payloads/` — request payloads for testing

   Show a brief summary of what changed.

4. **Context for the user**
   Explain what was generated:
   - **Schemas** (`quote-schema.json`, `application-schema.json`) — configure input forms in the Root dashboard or your frontend
   - **API docs** — describe the API shape for integrating with Root
   - **Payloads** — ready-to-use test payloads for `/rp-test` and `/rp-render`

---

## Troubleshooting

**`rp generate` runs but produces no output files:**

- The generator parses Joi schemas from `validateQuoteRequest` / `validateApplicationRequest` — if the Joi patterns don't match what the generator expects (e.g. nested custom validation, complex `.when()` clauses, or non-standard Joi usage), it may silently produce nothing.
- **Check**: After running, verify files exist in `./sandbox/`. If empty, the Joi schema may need simplification or the schemas should be hand-written in the Root array format.
- **Workaround**: Start schema files with `[]` (empty array) so `rp push` succeeds, then hand-build the array-format schema or simplify Joi validation until `rp generate` can parse it.
