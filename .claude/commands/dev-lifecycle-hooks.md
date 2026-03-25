# Dev Skill: Lifecycle Hooks and Scheduled Functions

Implement hooks that fire on policy events (e.g. payment success, cancellation) and scheduled functions that run on a time interval. Both return arrays of action objects — the platform queues and executes them.

## Steps

1. Read existing lifecycle hook and scheduled function files in `code/`
2. Identify which events this product needs to respond to (see hook reference below)
3. Implement each required hook — return `[]` for hooks with no logic
4. For `update_policy` actions, always spread `policy.module` and override only changed fields
5. Implement scheduled functions if time-based logic is needed (e.g. monthly premium review)
6. If creating new files, add them to `codeFileOrder` in `.root-config.json`
7. Write unit tests for hooks with meaningful logic, especially payment failure / lapse logic
8. Run `/rp-dev` to push the draft

→ Run `/rp-test` to verify

---

## Reference: hook signature

```js
const afterPolicyIssued = ({ policy, policyholder }) => {
  return [/* actions */];
};
```

## Reference: common lifecycle hooks

| Hook | Trigger |
|---|---|
| `afterPolicyIssued` | Policy issued |
| `afterPaymentSuccess` | Premium collected |
| `afterPaymentFailed` | Collection failed |
| `beforePolicyCancelled` | Policy about to cancel |
| `afterPolicyCancelled` | Policy cancelled |
| `beforePolicyReactivated` | Policy about to reactivate |
| `afterPolicyReactivated` | Policy reactivated |
| `afterClaimApproved` | Claim approved for payout |

## Reference: action types

```js
// Update policy data (always spread module)
{ name: 'update_policy', data: { module: { ...policy.module, key: value } } }

// Change status
{ name: 'cancel_policy' }
{ name: 'lapse_policy' }
{ name: 'reactivate_policy' }

// Ledger
{ name: 'credit_ledger', data: { amount: 5000, note: 'Loyalty bonus' } }

// Notification
{ name: 'send_notification', data: { type: 'policy_issued', email: policyholder.email } }

// No-op
return []
```

## Reference: grace period pattern (afterPaymentFailed)

```js
const afterPaymentFailed = ({ policy, policyholder }) => {
  const failedPayments = (policy.module.failed_payment_count || 0) + 1;
  if (failedPayments >= 3) return [{ name: 'lapse_policy' }];
  return [{
    name: 'update_policy',
    data: { module: { ...policy.module, failed_payment_count: failedPayments } },
  }];
};
```

## Reference: scheduled function format

Scheduled functions are **objects** with a `name` property and an async `run` method. They are **not** cron strings. The schedule (frequency, time, day) is configured in `.root-config.json` under `scheduledFunctions`, not in the code.

### Code definition

```js
const monthlyPremiumReview = {
  name: 'monthly_premium_review',
  run: async ({ policy, policyholder }) => {
    return [/* actions */];
  },
};
```

The `name` must match the `functionName` in `.root-config.json`.

### Config registration (`.root-config.json`)

```json
{
  "scheduledFunctions": [
    {
      "functionName": "monthly_premium_review",
      "policyStatuses": ["active"],
      "frequency": {
        "type": "monthly",
        "timeOfDay": "04:00",
        "dayOfMonth": 1
      }
    }
  ]
}
```

→ **CRITICAL**: Do **not** use cron syntax. The `frequency` object defines the schedule:
- `type`: `"daily"`, `"weekly"`, `"monthly"`, or `"yearly"`
- `timeOfDay`: `"H:00"` or `"H:30"` only (UTC)
- `dayOfMonth`: 1–28 (for monthly/yearly)
- `dayOfWeek`: `"monday"`–`"sunday"` (for weekly)
- `monthOfYear`: `"january"`–`"december"` (for yearly)

→ The `policyStatuses` array controls which policies the function runs against (e.g. `["active"]`, `["active", "lapsed"]`).

→ The `run` function is **async** — it can use `await` for SDK calls like `root.policies.list()`.
