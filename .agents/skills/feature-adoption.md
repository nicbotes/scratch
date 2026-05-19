---
name: feature-adoption
description: Measure adoption of a product feature — what fraction of a base population has the feature signal. Use when the user asks "how many policies / what % use feature X", "is take-up of the new benefit growing", or "who's not on the latest plan yet". Do NOT use for absolute counts only (run-query), per-user engagement rates (analyst-workflow), or building a recurring KPI dashboard view (jump straight to bi-view).
---

# Skill: feature-adoption

The canonical worked example for the framework. Turns a fuzzy "how many use X?" into: a precise feature predicate, a precise base population, a snapshot and a trend, with a regression golden so the answer is reproducible.

## Steps

1. **Clarify the feature signal.** One unambiguous predicate. Examples:
   - JSONB equality: `JSON_EXTRACT_SCALAR(module, '$.plan_type') = 'premium'`
   - JSONB presence: `JSON_EXTRACT(module, '$.rider_X') IS NOT NULL`
   - Column equality: `payment_method_type = 'debit_order'`
   If the predicate touches a JSONB column whose keys you don't know, run `derive-jsonb-schema` first.
2. **Clarify the base population.** One unambiguous filter. Defaults to consider with the user:
   - All policies in `$ROOT_ENV`.
   - Active policies only.
   - Policies created in a specific cohort window.
3. **Clarify the grain.** Default: snapshot today + monthly trend for the last 6 months. Confirm with the user before running.
4. **Profile the base population** (`profile-data`). Adoption against a stale or null-heavy base is noise.
5. **Compute the snapshot:**
   ```sql
   WITH base AS (
     SELECT policy_id, module
     FROM policies
     WHERE environment = '$ROOT_ENV'
       AND status = 'active'                                          -- <base filter>
   ),
   adopters AS (
     SELECT policy_id
     FROM base
     WHERE JSON_EXTRACT_SCALAR(module, '$.plan_type') = 'premium'     -- <feature signal>
   )
   SELECT
     (SELECT COUNT(*) FROM adopters)                                  AS adopters,
     (SELECT COUNT(*) FROM base)                                      AS base,
     1.0 * (SELECT COUNT(*) FROM adopters)
         / NULLIF((SELECT COUNT(*) FROM base), 0)                     AS adoption_rate
   ```
6. **Compute the trend:**
   ```sql
   SELECT
     date_trunc('month', from_iso8601_timestamp(created_at))      AS month,
     COUNT(*)                                                     AS base,
     COUNT_IF(JSON_EXTRACT_SCALAR(module, '$.plan_type')
              = 'premium')                                        AS adopters,
     1.0 * COUNT_IF(JSON_EXTRACT_SCALAR(module, '$.plan_type')
                    = 'premium') / NULLIF(COUNT(*), 0)            AS rate
   FROM policies
   WHERE environment = '$ROOT_ENV'
     AND status = 'active'
     AND from_iso8601_timestamp(created_at) >= NOW() - INTERVAL '6' MONTH
   GROUP BY 1
   ORDER BY 1
   ```
7. **Sanity check.** `adopters + non_adopters = base`. If they don't, find the missing rows before publishing.
8. **Persist by cadence:**
   - **One-off** → return the numbers in chat; add a parameterised entry to `references/examples.md` if the shape is novel.
   - **Recurring KPI** → hand off to `bi-view`; save as `fact_feature_adoption_<feature>_view` with monthly grain.
   - **Triggers ops follow-up** ("call non-adopters") → hand off to `ops-dataset`; save as `ops_<feature>_non_adopters_view`.
9. **Pin a regression golden** for the snapshot at a **closed** historical date so the next session can verify:
   ```bash
   bash .agents/tools/regression-record.sh feature_adoption_plan_premium_2025q1 \
     "WITH base AS (...filter active policies in 2025q1 closed range...),
          adopters AS (...same predicate...)
      SELECT (SELECT COUNT(*) FROM adopters) AS adopters,
             (SELECT COUNT(*) FROM base) AS base"
   ```

## Reference

Edge cases worth surfacing in the reply:
- **Optional keys vs missing rows.** `JSON_EXTRACT_SCALAR` on an absent key returns `NULL`. `NULL ≠ 'value'` so the adopter count is correct, but if the user's mental model is "what about rows that don't have the key at all?", call that out — the snapshot answers "adopters / total", not "users who opted in vs opted out".
- **Versioned plans.** If the same `plan_type` value means different things across module versions, restrict the base to one module version (use `product_module_id` if available) before computing.
- **Snapshot freshness.** Always state `max(created_at)` from the profile alongside the rate — "as of <date>, snapshot refreshed daily".

→ Cross-references: `derive-jsonb-schema` (for unknown JSONB shapes), `bi-view` (recurring KPIs), `ops-dataset` (action follow-up), `regression-test` (pin the historical answer), `references/extension-shapes.md` (when to persist as what).
