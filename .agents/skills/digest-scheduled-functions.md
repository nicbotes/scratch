---
name: digest-scheduled-functions
description: Read, interpret, and act on the weekly scheduled-function digest at `.agents/digests/<ISO-week>.md`. Use when the user asks "where should we attack next?", "did last week's targeting fix work?", "what's the digest say?", or wants to (re)generate the digest. Do NOT use for ad-hoc volume queries (use `ops-scheduled-function-volumes`) or for the canonical view docs (`bi/fact_scheduled_function_runs_view.md`).
---

# Skill: digest-scheduled-functions

The consumption layer for the cross-org scheduled-function tracking project. Producer is `tools/scheduled-function-digest.sh`; consumer is one in-house Root dev who's rewriting product-module scheduled functions to tighten targeting. The dev is flying blind today — no Lambda logs surfaced, no CloudWatch dashboard — so the digest IS their primary signal. Treat it that way: the headline is the next-PR queue, not a finance report.

## Producing the digest

```bash
set -a; source .agents/.env; set +a
bash .agents/tools/scheduled-function-digest.sh
# → writes .agents/digests/<ISO-week>.md + sibling .manifest.json
```

Other invocations:

```bash
# Inspect SQL + window dates without hitting Athena
bash .agents/tools/scheduled-function-digest.sh --explain

# Look at a prior week
bash .agents/tools/scheduled-function-digest.sh --weeks-back 1

# Tighten or widen the per-week window
bash .agents/tools/scheduled-function-digest.sh --window-days 14

# Tune the cost anchors (defaults: Lambda $0.0000167/s, Fargate $0.0000010/s)
bash .agents/tools/scheduled-function-digest.sh \
  --lambda-rate 0.0000167 --fargate-rate 0.0000010

# Remove the digest's own workspace immediately after (CSVs from cross-org-pull
# stay; clean those periodically with the find recipe below)
bash .agents/tools/scheduled-function-digest.sh --cleanup
```

## How to read it

### Summary

A one-row orientation: total compute-hours this week + Lambda/Fargate $ anchors + total runs + distinct functions + orgs covered. The lambda↔fargate spread (typically ~20×) is itself the useful signal — "this matters a lot, or barely at all, depending on where the workload runs."

### Hotspots — the next-PR queue

Ranked by compute-hours DESC, not run count. A slow-but-rare function can outweigh a fast-but-frequent one; the rank already accounts for both.

**Strong candidates for attack** (initial thresholds, refine over time):

- `compute_h >= 50` per week (~7 compute-hours per day — meaningful), **AND**
- `p99_over_p10 >= 10` (clear bimodality → there's a "did real work" tail to optimise toward by tightening targeting)

If `compute_h` is high but `p99_over_p10` is low (~3 or less), the function's duration distribution is flat. That can mean:
- Every run does real work (targeting is already tight; the lever is the work itself, not the targeting), or
- Every run is a no-op (the function should probably not exist at all).

Either way, duration alone can't tell you which; needs product-module-side reasoning. Open the function source.

### Notable movers

Biggest absolute compute-hour deltas vs prior week. Use this to confirm a targeting PR actually moved the number — the function it touched should drop down the leaderboard and appear here with a `↓ down` direction.

**The `↻` glyph matters.** When a function shows it, the function ran under more than one `product_module_definition_id` during the week — i.e. the module was deployed mid-week. The compute-hour delta might be a deploy artifact (v2 of the function is faster, or has different side effects, or fires on different policies), not a real targeting-loop change. Investigate before celebrating.

### Per-client rollup

Sanity-check that the cross-org pull worked. If a client expected to be in `ROOT_ORG_IDS` is missing, the per-client rollup is the place you notice (likely cause: view not saved into that org's workgroup, or Athena bucket override missing).

### NULL `completed_at`

Separate signal from "no-op". A row with NULL `completed_at` is either crashed or still-running at snapshot time. Crashes are waste-of-a-different-kind: real work attempted, didn't complete. If a function has a high NULL-rate, that's worth its own investigation (probably an unhandled exception path).

## What the digest does NOT tell you

- **True no-op counts.** Per the view doc, `duration_ms` is a proxy. Anything inferred from it is approximate. To know "function X actually did real work R% of the time", you need product-module-side instrumentation (counters in the function body).
- **Cost truth.** Lambda and Fargate are anchors, not Root's actual hosting bill. If the dev needs a defensible $ number for budget conversations, take the compute-hours figure to whoever owns the hosting cost basis.
- **What to do.** The digest tells you WHICH function to attack; the HOW is in the product module's source — read the function body, find what condition it's filtering on internally, hoist that into a pre-filter (either at the platform-feature level, see FUTURE work, or at minimum a SQL pre-filter inside the function that exits early before any work).
- **Latency, errors, side effects.** Function-level metrics only. If a scheduled function calls out to an upstream service, that's invisible here.

## When to suspect the digest is wrong

- **Numbers swing wildly week-over-week with no targeting work shipped.** Likely cause: a `product_module_definition_id` change (look for `↻` glyphs) or Athena snapshot lag on the most recent day. Re-run `--weeks-back 1` to compare against a known-good prior week.
- **A function appears with `<unknown>` product.** The `rp_dim_product_view` join missed; either the product module was created after the dim's last snapshot, or it was deleted. Cross-check with `dim-product` directly.
- **A whole client is missing.** Check `cross-org-pull.sh` stderr from the last digest run (or re-run with `--explain` to verify the pull SQL); the most common cause is the view not being saved into that org's workgroup, or `ROOT_ATHENA_S3_BUCKET_BY_ORG` missing an override.
- **No movers section / no prior-week data.** First run for a new ISO week, or the prior-week dates fall outside Athena's retention window.

## Workflow — the loop the digest exists to enable

1. **Monday**: `bash .agents/tools/scheduled-function-digest.sh`. Open `.agents/digests/<ISO-week>.md`. Scan the Hotspots table.
2. Pick the top candidate matching `compute_h >= 50 AND p99_over_p10 >= 10`. Note the function + product + client.
3. Open the product module source (\`rp clone\` if not local). Find the scheduled function. Identify the condition it's filtering on inside its body.
4. Refactor: hoist the condition into a SQL pre-filter (via `root.policies.find` with the right `where:` clause) so the function body only runs on candidate policies. Or, if the function is truly per-policy-event, switch it from a scheduled to a lifecycle hook on the trigger event.
5. Test, deploy. Note the deploy date.
6. **Next Monday**: re-run the digest. Confirm the function appears in **Notable movers** with `↓ down`. If it has a `↻` glyph, the delta is partly a deploy artifact — read both definitions and confirm the drop is real.
7. Pick the next candidate. Repeat.

## Cleanup

The digest's own workspace (`.agents/cross-org/<ts>-digest/`) is removable with `--cleanup` on each run. `cross-org-pull.sh` creates its own per-invocation workspace under `.agents/cross-org/<ts>/` that this flag does NOT touch — those accumulate over time. Periodically:

```bash
find .agents/cross-org -mtime +90 -type d -exec rm -rf {} +
```

90 days is conservative; tune to taste. Digests themselves (`.agents/digests/*.md`) are small and worth keeping indefinitely — they're the longitudinal record of the targeting project.

## Cross-references

- `bi/fact_scheduled_function_runs_view.md` — the underlying view (column meanings, carve-pattern definitions, audit query)
- `skills/ops-scheduled-function-volumes.md` — the ad-hoc volume-query layer this skill consumes
- `skills/cross-org-explore.md` — the cross-org fan-out pattern
- `references/data-trust.md` — the `[single-source]` confidence-label convention used in the digest header
- `tools/scheduled-function-digest.sh` — the producer
- `tools/cross-org-pull.sh` — the underlying fan-out tool

→ Cross-references: [`bi/fact_scheduled_function_runs_view.md`](../bi/fact_scheduled_function_runs_view.md), [`skills/ops-scheduled-function-volumes.md`](./ops-scheduled-function-volumes.md), [`references/data-trust.md`](../references/data-trust.md), [`tools/scheduled-function-digest.sh`](../tools/scheduled-function-digest.sh).
