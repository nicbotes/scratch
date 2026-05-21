---
name: scope-clarify
description: Disambiguate whether a question is universal (every client behaves the same) or client-specific (commercial-model logic varies by client), then route to the right analytical layer. Use when the user names a specific client, uses commercial-model language (invoice, Bordereau, ceded premium, profit share), or asks anything where the universal fact_/dim_ layer might not be enough. Do NOT use when the question is clearly universal across all clients (use analyst-workflow), or when a client is mentioned only as a filter on universal data ("policies for X created in 2025" — that's analyst-workflow with a WHERE clause).
---

# Skill: scope-clarify

The boundary-awareness skill. Determines whether you're in **universal analytical territory** (every client behaves the same — `rp_fact_payments_view`, `rp_dim_policyholder_view`) or **per-client commercial-model territory** (invoicing, Bordereau, ceded premium splits — `rp_fact_invoice_<client>_view`).

The two layers exist because commercial models diverge by client. One bloated view with `CASE WHEN client_id = 'acme' THEN ...` branches is the wrong shape; per-client views with the same Kimball discipline are the right shape.

## Steps

1. **Identify the client.** Match the user's brand name / id reference to a slug in `references/clients.txt`. If unrecognised, ask the user to confirm the slug or add it to the registry — never invent a slug.

2. **Classify the question shape:**

   | Shape | Example | Route to |
   |---|---|---|
   | **Universal** — analytical question true for every client | "How many active policies do we have?", "Payment failure rate this quarter" | `analyst-workflow` against `rp_fact_*_view` / `rp_dim_*_view` |
   | **Filter on universal** — client mentioned only as a `WHERE` filter | "Active policies for ACME", "ACME's payment failures this quarter" | `analyst-workflow` with `WHERE organization_id = '<acme-uuid>'` |
   | **Client-bespoke commercial** — commercial model varies by client | "ACME's invoice for Q1", "Bordereau for GlobalCorp's reinsurance treaty", "Profit share with Mutual" | `bi-view` (per-client variant) — builds/uses `rp_fact_invoice_<client>_view` etc. |
   | **Mixed** — universal computation, client-specific framing | "Compute ACME's total premium, then apply their 30% ceded split" | Disambiguate explicitly in reply. Universal portion → `rp_fact_payments_view`. Client-specific portion → per-client view. State both in the reply. |

3. **Check the per-client layer state** before proceeding:
   - `ls .agents/bi/clients/<slug>/` and `ls .agents/ops/clients/<slug>/` for existing docs.
   - Or `bash .agents/tools/framework-status.sh` for the dashboard summary.
   - **Stable views exist** → use them. Cite the view names in your reply.
   - **No views yet** → start in scratch first (`save-view.sh --scratch [<ns>] <body>`), promote to `rp_fact_<entity>_<client>_view` via `bi-view` once the shape is stable. Document in `.agents/bi/clients/<slug>/<entity>.md`.

4. **Cite the layer in your reply.** Tell the user which kind of work they're getting and why. Example:
   - "I'm running this against ACME's per-client invoice view (`rp_fact_invoice_acme_view`); it reads from the universal `rp_fact_payments_view` and applies ACME's specific cession terms from `rp_dim_client_terms_view`."
   - This makes the boundary visible — the user knows what part of the answer is universal vs commercial, and can sanity-check accordingly.

5. **If mixed, structure the reply as two passes:**
   - Pass 1: universal aggregate (counts, sums) — small summary, lands in context.
   - Pass 2: client-specific transformation — applied to the result of pass 1. Either inline if simple, or via the per-client view if recurring.

## When to promote scratch → per-client → dbt

| State | Sign | Next step |
|---|---|---|
| Exploring a new commercial model | One-off SQL, not yet pinned | Stay in `rp_scratch_<ns>_*_view` |
| Stable per-client logic, one consumer | Repeated use, one team reads it | Promote to `rp_fact_<entity>_<client>_view`; doc in `.agents/bi/clients/<slug>/` |
| ≥3 clients with stable bespoke views, ≥2 downstream consumers each | Maturity flag in `framework-status.sh` fires | Consider dbt promotion (FUTURE.md §9). Per-client views become the spec for dbt staging models. |

→ Cross-references: `references/per-client-analysis.md` (the full convention doc); `bi-view` (per-client variant section); `ops-dataset` (per-client variant section); `framework-status.sh` (maturity dashboard); FUTURE.md §9 (dbt destination).
