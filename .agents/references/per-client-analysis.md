# Reference: Per-client analysis layer

The framework has two analytical layers. Knowing which one your question belongs in is the first decision; getting it wrong creates a tax that compounds across sessions.

| Layer | What it encodes | Owned by | Naming |
|---|---|---|---|
| **Universal** | Platform-shaped facts true for every client (policies, claims, payments, policyholder dims) | The platform data model | `rp_fact_*_view`, `rp_dim_*_view`, `rp_ops_*_view` |
| **Per-client commercial** | Commercial-model artefacts that diverge by client (invoicing, Bordereaux, ceded splits, profit share) | The client engagement | `rp_fact_<entity>_<client>_view`, `rp_dim_<entity>_<client>_view`, `rp_ops_<action>_<client>_view` |

## What goes in the universal layer

Anything **true for every client**, derived only from platform tables:

- `rp_fact_payments_view` — payment events, regardless of which client owns the policy
- `rp_fact_policies_view` — policy facts (start, end, status, premium-cents)
- `rp_dim_policyholder_view` — current attributes per policyholder (SCD1)
- `rp_dim_product_view` — product module → product name, line of business
- `rp_dim_date_view` — calendar with fiscal markers
- `rp_dim_payment_method_view` — method types, statuses, normalised

These are owned by the platform's data model. They evolve when the platform's schema evolves, not when a customer arrangement changes.

## What goes in the per-client layer

Anything that **varies by client commercial arrangement**:

- `rp_fact_invoice_<client>_view` — what client X is invoiced this period, computed per their contract terms
- `rp_fact_bordereau_<client>_view` — reinsurance treaty Bordereau for client X with their cession percentages
- `rp_fact_profit_share_<client>_view` — profit-share computation per their formula
- `rp_dim_client_terms_view` — a *conformed* dimension holding contract terms for all clients (cession percentages, commission rates, fee schedules). Lives in `bi/clients/_shared/` because it's per-client *data*, not per-client *view*.
- `rp_ops_<action>_<client>_view` — operational queues that depend on a client's commercial model (e.g. "ACME's late-fee escalation queue" if late fees only apply to ACME)

These are owned by the client engagement. They evolve when a contract is amended, when a new commercial product is offered to a specific client, or when a client's data needs differ from the platform default.

## The naming convention (strict)

| Pattern | Example | Doc path |
|---|---|---|
| `rp_fact_<entity>_view` | `rp_fact_payments_view` | `.agents/bi/fact_payments_view.md` |
| `rp_dim_<entity>_view` | `rp_dim_policyholder_view` | `.agents/bi/dim_policyholder_view.md` |
| `rp_ops_<action>_view` | `rp_ops_failed_payments_to_retry_view` | `.agents/ops/ops_failed_payments_to_retry.md` |
| `rp_fact_<entity>_<client>_view` | `rp_fact_invoice_acme_view` | `.agents/bi/clients/acme/fact_invoice.md` |
| `rp_dim_<entity>_<client>_view` | `rp_dim_product_segment_acme_view` | `.agents/bi/clients/acme/dim_product_segment.md` |
| `rp_ops_<action>_<client>_view` | `rp_ops_invoice_reconcile_acme_view` | `.agents/ops/clients/acme/ops_invoice_reconcile.md` |
| `rp_scratch_<ns>_*_view` | `rp_scratch_nic_invoice_acme_v3_view` | (undocumented by design) |

The view name in Athena is **always** `rp_<prefix>_<entity>[_<client>]_view`. The `rp_` is automatic (`save-view.sh` prepends it). The doc path encodes the client in the directory, not the filename.

The client slug must:
- Match `^[a-z][a-z0-9-]*$` (kebab-case, starts with a letter)
- Be present in `references/clients.txt` (warning, not error, if missing)

Entity-first grouping in the view name keeps `SHOW VIEWS` clustered by *what kind* of artefact (`rp_fact_invoice_*` shows every client's invoice fact together — useful when an analyst asks "who has invoice views?").

## The graduation path

```
   exploration               case-by-case Kimball              dbt-owned mart
       │                           │                                 │
       ▼                           ▼                                 ▼
  scratch view  ─► per-client fact view  ─► dbt model with tests, lineage,
  (rp_scratch_)    (rp_fact_<entity>_         scheduled refresh, docs site
                   <client>_view)
                                       ▲
                                       │
                            trigger: ≥3 clients on stable
                            commercial models AND ≥2
                            downstream consumers each
                            (per FUTURE.md §9)
```

The framework is genuinely well-suited for **stages 1 and 2**. Stage 3 (dbt) is the destination state once volume and stability demand the things dbt gives you for free (dependency graphs, model tests, scheduled refresh, lineage).

**Do not skip stages.** Building dbt before stable per-client views is premature — you'll be debugging dbt's compile errors instead of nailing the commercial logic. Build the per-client views first; the dbt project follows naturally with the views as its spec.

## Common pitfalls

- **Don't duplicate logic across client views** when the calculation is the same with a different number. Introduce a `rp_dim_client_terms_view` that holds the parameters (cession percentages, commission rates, fee schedules); every `rp_fact_invoice_<client>_view` joins to it. Cession % differing by client doesn't justify three full fact views — it justifies one terms dim and three thin per-client facts that join to it.

- **Don't put PII in per-client views.** All the PII rules (#26–#28) still apply. Per-client commercial views typically aggregate over policyholders; they shouldn't need names or emails. If they do, route through `pii-safe-analysis`.

- **Don't rename a view in place when promoting.** Scratch → per-client → dbt are *additive* steps. Create the new name; switch consumers; drop the old one only after consumers have moved. Athena view DDL isn't transactional; an in-place rename can leave a query staring at a dropped name mid-flight.

- **Don't let scratch views accumulate forever.** A `rp_scratch_*` view that hasn't been touched in a sprint is a candidate for deletion or promotion. `framework-status.sh` will flag this when the retro maturity pass lands (Phase 8).

- **Don't fight the convention.** If a question doesn't fit either layer cleanly, the answer isn't a third layer — it's that you haven't disambiguated the question yet. Run `scope-clarify` and split.

## Quick reference: which skill for which shape

| Question | Skill |
|---|---|
| "How many active policies do we have?" | `analyst-workflow` |
| "ACME's policies created in 2025" (universal filtered) | `analyst-workflow` with WHERE filter |
| "ACME's invoice for Q1" (commercial model) | `scope-clarify` → `bi-view` (per-client variant) |
| "What's the Bordereau for GlobalCorp's treaty?" | `scope-clarify` → `bi-view` (per-client variant) |
| "Who do we need to call about late payments today?" (universal ops) | `ops-dataset` |
| "ACME's late-fee escalation queue" (per-client ops) | `scope-clarify` → `ops-dataset` (per-client variant) |
| "Show me the dbt path" | FUTURE.md §9 |

→ Cross-references: `skills/scope-clarify.md` (routing); `skills/bi-view.md` (Kimball + per-client variant); `skills/ops-dataset.md` (operational + per-client variant); `references/clients.txt` (registry); `tools/framework-status.sh` (maturity dashboard); `FUTURE.md` §9 (dbt destination).
