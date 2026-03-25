# Dev Skill: Data Exports

Configure scheduled or ad-hoc data exports from the Root platform — CSV files delivered to SFTP, S3, or HTTPS endpoints. Exports use Handlebars templates to select fields from 13 data sources.

## Steps

1. Identify which data the client needs exported (policies, payments, claims, charges, etc.)
2. Choose the data source from the 13 available (see reference below)
3. Create an export template using Handlebars syntax — each field becomes a CSV column
4. Configure the delivery method: SFTP, S3, or HTTPS endpoint
5. Set the schedule: daily, weekly, or monthly
6. Set the data range filter: today, week-to-date, month-to-date, full history, or since-last-run (scheduled only)
7. Test with an ad-hoc export using a custom date range before enabling the schedule
8. Configure on the Root Dashboard: Data Management → Data Exports

→ Charges breakdown in exports requires `charges` on the policy — see `/dev-quote-hook` (costs and charges pattern)
→ For SQL-based querying instead of flat files, see `/dev-data-adapter`

---

## Reference: available data sources

| Data source | Objects included |
|---|---|
| `applications` | Application, Policyholder |
| `claims` | Claim, Policyholder, Policy |
| `complaints` | Complaint, Policyholder, Policy |
| `debicheck_mandates` | DebiCheck mandate, Payment method, Policyholder |
| `notifications` | Notification |
| `payment_methods` | Payment method |
| `payment_coupons` | Payment coupon |
| `payments` | Payment, Policyholder, Payment method |
| `payout_requests` | Payout request, Policyholder, Policy, Claim |
| `policies` | Policy, Policyholder |
| `policy_charges` | Payment, Policyholder |
| `policy_premiums` | Payment, Policyholder |
| `policyholders` | Policyholder |

## Reference: export template (Handlebars)

Each template maps to one data source. Fields become CSV columns.

```handlebars
{{policy.policy_id}},{{policy.policy_number}},{{policy.status}},{{policy.monthly_premium}},{{policyholder.first_name}},{{policyholder.last_name}},{{policyholder.email}}
```

**Module data access:**
```handlebars
{{policy.module.cover_amount}},{{policy.module.age}},{{policy.module.plan_type}}
```

**Metadata fields** (optional):
```handlebars
{{row_number}},{{export.created_at}},{{export.status}},{{export.file_id}}
```

## Reference: delivery methods

| Method | Config needed |
|---|---|
| SFTP | Host, port, username, password or SSH key, remote path |
| S3 | Bucket name, region, access key, secret key, prefix path |
| HTTPS | Endpoint URL (POST with CSV payload) |

## Reference: schedule and data range

| Schedule | Options |
|---|---|
| Frequency | Daily, weekly, monthly |
| Data range (scheduled) | Today, week-to-date, month-to-date, full history, since last run |
| Data range (ad-hoc) | Custom date range, or any of the above |

Data is filtered on the `created_at` field of each record. All exports generate CSV files.

## Reference: common export patterns

**Monthly policy report:**
- Source: `policies`
- Range: month-to-date
- Fields: policy_id, policy_number, status, monthly_premium, sum_assured, start_date, policyholder name/email

**Payment reconciliation:**
- Source: `payments`
- Range: since last run
- Fields: payment_id, policy_id, amount, status, payment_date, payment_type, payment_method type

**Claims summary:**
- Source: `claims`
- Range: month-to-date
- Fields: claim_id, policy_id, status, approval_status, created_at, module data
