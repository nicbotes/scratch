# Reference: Athena Table Catalog

Tables exposed in every org's Athena database (`$ROOT_ORG_ID`). All tables have an `environment` column (`production` | `sandbox`) — every query must filter on it (rules.md #1).

> Run `bash .agents/tools/athena-describe.sh <table>` to see the live column list. The catalog below covers the columns the agent uses most often; sample the table for less-common columns rather than guessing.

## `organisations`

The lookup the `whoami` skill depends on. The org id stored here matches `$ROOT_ORG_ID` (which is also the workgroup / database / S3 prefix).

| Column | Type | Notes |
|---|---|---|
| `id` | varchar | The org id — same string as workgroup/schema/S3 prefix |
| `name` | varchar | Human-readable name printed by `whoami` |

(Other columns exist — run `DESCRIBE organisations` to see them.)

## `policies`

| Column | Notes |
|---|---|
| `policy_id`, `policy_number` | Identifiers |
| `status` | `active`, `lapsed`, `cancelled`, `expired`, etc. |
| `monthly_premium`, `sum_assured` | **Cents** (rules.md #2) |
| `module`, `charges` | JSON varchar — `JSON_EXTRACT_SCALAR` (rules.md #5) |
| `start_date`, `end_date`, `created_at` | ISO 8601 — wrap with `from_iso8601_timestamp` |
| `policyholder_id` | FK to `policyholders` |

## `policyholders`

PII-heavy. Use carefully in queries that leave the framework.

| Column | Notes |
|---|---|
| `policyholder_id` | Identifier |
| `first_name`, `last_name`, `email` | PII |
| `id_number`, `date_of_birth` | PII (national id) |

## `payments`

| Column | Notes |
|---|---|
| `payment_id`, `policy_id`, `payment_method_id` | Identifiers |
| `amount` | **Cents** |
| `status` | `successful`, `failed`, `pending`, `reversed` |
| `payment_type`, `payment_date` | `payment_date` is ISO 8601 |

## `claims`

| Column | Notes |
|---|---|
| `claim_id`, `policy_id` | Identifiers |
| `status`, `approval_status` | Workflow state |
| `module` | JSON — claim-specific data |
| `created_at` | ISO 8601 |

## `policy_ledger`

| Column | Notes |
|---|---|
| `policy_id`, `amount`, `currency` | `amount` in cents |
| `description`, `created_at` | |

## `policy_events`

| Column | Notes |
|---|---|
| `policy_id`, `event_type` | |
| `data` | JSON varchar — event payload |
| `created_at` | ISO 8601 |

## `payment_methods`

| Column | Notes |
|---|---|
| `payment_method_id`, `policy_id` | |
| `type`, `status` | |

## `notifications`

| Column | Notes |
|---|---|
| `notification_id`, `policy_id`, `type`, `status`, `created_at` | |

## `users`

| Column | Notes |
|---|---|
| `user_id`, `email`, `role` | Dashboard / API users — not policyholders |

## `product_module_definitions`

| Column | Notes |
|---|---|
| `product_module_id`, `settings`, `billing` | Configuration snapshots |

→ When a query reveals new columns (or new tables), call `observe --kind reference-thrash --target .agents/references/schema.md` so the next retro promotes them in.
