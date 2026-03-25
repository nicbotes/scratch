# Dev Skill: Lifecycle Hooks and Scheduled Functions

Implement or update lifecycle hooks and scheduled functions. These run automatically in response to policy events (lifecycle hooks) or on a time schedule (scheduled functions).

## Concepts

- **Lifecycle hooks** — triggered by platform events (policy issued, payment succeeded, claim approved, etc.)
- **Scheduled functions** — run on a regular interval (daily, monthly, etc.) against all active policies
- Both return **arrays of action objects** that the platform queues and executes

## Common Lifecycle Hooks

| Hook | Trigger |
|---|---|
| `afterPolicyIssued` | Policy is issued |
| `afterPaymentSuccess` | Premium collected successfully |
| `afterPaymentFailed` | Premium collection failed |
| `beforePolicyCancelled` | Policy about to be cancelled |
| `afterPolicyCancelled` | Policy has been cancelled |
| `beforePolicyReactivated` | Policy about to be reactivated |
| `afterPolicyReactivated` | Policy reactivated |
| `afterClaimApproved` | Claim approved for payout |

## Hook Signature

```js
const afterPolicyIssued = ({ policy, policyholder }) => {
  // Return an array of actions
  return [
    // actions here
  ];
};
```

## Scheduled Function Signature

```js
const monthlyCheck = {
  name: 'monthly_premium_review',
  schedule: '0 9 1 * *', // cron: 9am on the 1st of each month
  run: ({ policy, policyholder }) => {
    return [
      // actions here
    ];
  },
};
```

## Action Types

Actions are objects returned from hooks/functions. The platform processes them in order.

**Update policy data:**
```js
{
  name: 'update_policy',
  data: {
    module: {
      ...policy.module,
      last_reviewed: new Date().toISOString(),
    },
  },
}
```

**Change policy status:**
```js
{ name: 'cancel_policy' }
{ name: 'lapse_policy' }
{ name: 'reactivate_policy' }
```

**Credit/debit the ledger:**
```js
{
  name: 'credit_ledger',
  data: { amount: 5000, note: 'Loyalty bonus' },
}
```

**Send a notification:**
```js
{
  name: 'send_notification',
  data: {
    type: 'policy_issued',
    email: policyholder.email,
  },
}
```

**No-op (nothing to do):**
```js
return []; // empty array is valid
```

## Example: afterPolicyIssued

```js
const afterPolicyIssued = ({ policy, policyholder }) => {
  return [
    {
      name: 'update_policy',
      data: {
        module: {
          ...policy.module,
          issued_at: new Date().toISOString(),
        },
      },
    },
  ];
};
```

## Example: afterPaymentFailed (grace period logic)

```js
const afterPaymentFailed = ({ policy, policyholder }) => {
  const failedPayments = (policy.module.failed_payment_count || 0) + 1;

  if (failedPayments >= 3) {
    return [
      { name: 'lapse_policy' },
    ];
  }

  return [
    {
      name: 'update_policy',
      data: {
        module: {
          ...policy.module,
          failed_payment_count: failedPayments,
        },
      },
    },
  ];
};
```

## File Placement

- `code/08-lifecycle-hooks.js`
- `code/09-scheduled-functions.js`

## Steps

1. Read the existing lifecycle hook and scheduled function files (if any)
2. Identify which events this product needs to respond to
3. Implement the relevant hooks — return empty arrays for hooks with no logic
4. Implement scheduled functions if time-based logic is needed (e.g. anniversary premium review)
5. Use `update_policy` actions to mutate `policy.module` — always spread existing module data
6. Write unit tests for hooks with meaningful logic (especially payment failure / lapse logic)
7. Run `/rp-dev` to push the draft
