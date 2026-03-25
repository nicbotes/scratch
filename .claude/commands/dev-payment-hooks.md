# Dev Skill: Payment and Coupon Lifecycle Hooks

Implement payment lifecycle hooks (payment success, failure, reversal) and payment coupon hooks. These are the most commonly implemented lifecycle hooks — they drive grace period logic, failed payment tracking, and coupon workflows.

## Steps

1. Read existing lifecycle hooks in `code/` to check for payment-related hooks
2. Implement `afterPaymentSuccess({ policy, policyholder, payment })` — reset failed payment counters, activate policy if needed
3. Implement `afterPaymentFailed({ policy, policyholder, payment })` — track failure count, escalate toward lapse
4. Implement `afterPaymentReversed({ policy, policyholder, payment })` if the product handles reversals (payment object has `payment_type: 'reversal'` and `reversal_of_payment_id`)
5. If using payment coupons, implement `beforePaymentCouponCreated` to validate coupon creation rules
6. Implement `afterPaymentCouponRedeemed` if coupon use should trigger policy state changes
7. Implement `afterPaymentCouponCancelled` and `afterPaymentCouponReversed` as needed
8. If creating new files, add them to `codeFileOrder` in `.root-config.json`
9. Write unit tests for payment failure escalation logic
10. Run `/rp-dev` to push the draft

→ Payment hooks return actions — see `/dev-actions` for the full reference
→ Billing retry settings affect how often `afterPaymentFailed` fires — see `/dev-billing`
→ Run `/rp-test` to verify

---

## Reference: payment hook signatures

```js
const afterPaymentSuccess = ({ policy, policyholder, payment }) => {
  // Reset failed count on successful collection
  return [{
    name: 'update_policy',
    data: { module: { ...policy.module, failed_payment_count: 0 } },
  }];
};

const afterPaymentFailed = ({ policy, policyholder, payment }) => {
  // Track failures, escalate toward lapse
  const failedCount = (policy.module.failed_payment_count || 0) + 1;
  if (failedCount >= 3) return [{ name: 'lapse_policy' }];
  return [{
    name: 'update_policy',
    data: { module: { ...policy.module, failed_payment_count: failedCount } },
  }];
};

const afterPaymentReversed = ({ policy, policyholder, payment }) => {
  // payment.payment_type === 'reversal'
  // payment.reversal_of_payment_id references the original payment
  // payment.amount is negative
  return [];
};
```

## Reference: payment coupon hooks

All coupon hooks receive `{ policy, policyholder }` plus coupon-specific params.

| Hook | Extra params | Purpose |
|---|---|---|
| `beforePaymentCouponCreated` | `newPaymentCoupons` | Validate — throw to prevent creation |
| `afterPaymentCouponCreated` | `paymentCoupons` | React to new coupons |
| `afterPaymentCouponCancelled` | `paymentCoupons` | React to cancellation |
| `afterPaymentCouponRedeemed` | `paymentCoupons` | React to coupon use |
| `afterPaymentCouponReversed` | `paymentCoupons` | React to reversal |

```js
const beforePaymentCouponCreated = ({ policy, policyholder, newPaymentCoupons }) => {
  if (policy.status !== 'active') {
    throw new Error('Payment coupons can only be created for active policies');
  }
  return [];
};
```

## Reference: payment failure escalation pattern

```js
const afterPaymentFailed = ({ policy, policyholder, payment }) => {
  const failedCount = (policy.module.failed_payment_count || 0) + 1;
  const actions = [{
    name: 'update_policy',
    data: { module: { ...policy.module, failed_payment_count: failedCount } },
  }];

  // Notify policyholder
  if (failedCount >= 2) {
    actions.push({
      name: 'trigger_custom_notification_event',
      custom_event_key: 'payment_warning',
      custom_event_type: 'policy',
      policy_id: policy.policy_id,
    });
  }

  return actions;
};
```
