# Dev Skill: Root SDK Reference

Use the Root SDK (`root` global object) in product module code to query policies, manage payments and coupons, access data stores, send notifications, and retrieve secrets.

## Steps

1. **ALWAYS use the SDK** instead of raw `fetch()` calls to Root API endpoints
2. Use `root.policies.getPolicy(policyId)` to fetch a single policy by ID
3. Use `root.policies.getPolicies({ filters, pagination })` to query multiple policies
4. Use `root.policies.getPolicyPayments(policyId, { filters, pagination })` for payment history
5. Use `root.dataStores.store(key).find()` to read data from shared data stores
6. Use `root.notifications.triggerCustomEvent()` to fire custom notification workflows
7. Use `root.secretKeys.getSecretKeyByType({ type })` to retrieve stored secrets for external API auth
8. Use `root.policies.sendMail()` to send custom MJML emails linked to a policy

→ SDK methods are commonly used inside lifecycle hooks — see `/dev-lifecycle-hooks`
→ For runtime globals (moment, Joi, node-fetch), see `/dev-globals`

---

## Reference: root.policies

```js
// Single policy
const policy = await root.policies.getPolicy(policyId);

// Query policies
const policies = await root.policies.getPolicies({
  filters: { policyNumbers: ['POL123'] },
  pagination: { offset: 1, limit: 50 },
});

// Policy events
const events = await root.policies.getPolicyEvents(policyId);

// Payments with filters
const payments = await root.policies.getPolicyPayments(policyId, {
  filters: { statuses: ['successful'], paymentDateFrom: '2025-01-01' },
  pagination: { offset: 1, limit: 25 },
});

// Count payments
const count = await root.policies.countPolicyPayments(policyId, {
  filters: { statuses: ['successful'] },
});

// Send custom email (MJML)
await root.policies.sendMail({
  subject: 'Your policy documents',
  mjml: '<mjml><mj-body>...</mj-body></mjml>',
  to: { email: 'customer@example.com', name: 'Customer' },
  from: { email: 'support@company.com', name: 'Support' },
  policyId: policyId,
});
```

## Reference: root.policies payment coupons

```js
// List coupons
const coupons = await root.policies.getPaymentCoupons({
  policyId,
  filters: { status: ['active'] },
  includes: { policy: true },
});

// Create coupons
await root.policies.createPaymentCoupons({
  policyId,
  newPaymentCoupons: [
    { type: 'credit', amount: 10000, reason: 'Goodwill', redeemableFrom: '2026-02-01' },
  ],
});

// Cancel / redeem / reverse
await root.policies.cancelPaymentCoupon({ paymentCouponId });
await root.policies.redeemPaymentCoupon({
  paymentCouponId,
  action: { paymentDate: '2026-02-01' },
});
await root.policies.reversePaymentCoupon({ paymentCouponId });
```

## Reference: root.dataStores

```js
// Read all entities from a data store
const entities = await root.dataStores.store('rate-table').find();
```

## Reference: root.notifications

```js
await root.notifications.triggerCustomEvent({
  customEventKey: 'welcome-message',
  customEventType: 'policy',    // policy | payment_method | payment | claim
  id: policyId,                 // policy_id, payment_id, or claim_id depending on type
});
```

## Reference: root.secretKeys

```js
// Retrieve a stored secret (e.g. external API key)
const key = await root.secretKeys.getSecretKeyByType({ type: 'external_pricing_api_key' });
```

## Reference: root.organizations

```js
const users = await root.organizations.getUsers({
  filters: { search: 'alex', roleId: 'role_123' },
  pagination: { offset: 1, limit: 20 },
});
```
