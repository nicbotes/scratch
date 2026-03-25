# Dev Skill: Actions Reference

Complete reference for all action objects returned by lifecycle hooks, scheduled functions, and claims hooks. Actions are queued by the platform and executed in array order.

## Steps

1. Review which hooks in your product module return actions (lifecycle hooks, scheduled functions, claims hooks)
2. Use `update_policy` to modify policy data — always spread `policy.module` and override only changed fields
3. Use status actions (`activate_policy`, `cancel_policy`, `lapse_policy`, `mark_policy_not_taken_up`) to change policy state
4. Use ledger actions (`debit_policy`, `credit_policy`) to adjust the policy balance — amounts in cents
5. Use `trigger_custom_notification_event` to send notifications from hooks
6. Use `update_claim_module_data` in claims hooks to update claim-specific data
7. Return `[]` (empty array) from any hook that should be a no-op
8. Multiple actions in a single array execute in the order specified

→ Actions are returned by `/dev-lifecycle-hooks`, `/dev-claims-hook`, and `/dev-payment-hooks`

---

## Reference: update_policy

**CRITICAL**: Data properties use `camelCase`, not the `snake_case` seen on the policy object.

| Data property | Policy field | Type |
|---|---|---|
| `monthlyPremium` | `monthly_premium` | integer (cents) |
| `basePremium` | `base_premium` | integer (cents) |
| `billingAmount` | `billing_amount` | integer (cents) |
| `billingDay` | `billing_day` | integer (1-31) or null |
| `sumAssured` | `sum_assured` | integer (cents) |
| `module` | `module` | object (full replacement) |

```js
// Update module — ALWAYS spread existing, override changed fields
return [{
  name: 'update_policy',
  data: {
    module: { ...policy.module, failed_count: 0 },
  },
}];

// Update premium and module together
return [{
  name: 'update_policy',
  data: {
    monthlyPremium: newPremium,
    basePremium: newPremium,
    module: { ...policy.module, premium_updated_at: moment().format() },
  },
}];
```

## Reference: status change actions

```js
{ name: 'activate_policy' }

{
  name: 'cancel_policy',
  reason: 'Non-payment',
  cancellation_requestor: 'client',   // optional
  cancellation_type: 'Alternate product', // optional
}

{ name: 'lapse_policy' }

{ name: 'mark_policy_not_taken_up' }
```

## Reference: ledger actions

```js
// Debit — increases outstanding balance
{
  name: 'debit_policy',
  amount: 10000,          // cents
  description: 'Reactivation penalty',
  currency: 'ZAR',
}

// Credit — reduces outstanding balance
{
  name: 'credit_policy',
  amount: policy.balance,
  description: 'Forgive outstanding balance',
  currency: 'ZAR',
}
```

## Reference: trigger_custom_notification_event

```js
{
  name: 'trigger_custom_notification_event',
  custom_event_key: 'policyholder_birthday',
  custom_event_type: 'policy',       // policy | payment_method | payment | claim
  policy_id: policy.policy_id,       // required if type is policy or payment_method
  // payment_id: '...',              // required if type is payment
  // claim_id: '...',                // required if type is claim
}
```

## Reference: update_claim_module_data

Used in claims hooks only. Merges with existing claim module data.

```js
{
  name: 'update_claim_module_data',
  data: { review_notes: 'Auto-flagged for high value' },
}
```
