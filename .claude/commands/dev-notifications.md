# Dev Skill: Notifications (Email and SMS)

Trigger custom email and SMS notifications from product module code — via lifecycle hook actions, the Root SDK, or direct MJML email sending.

## Steps

1. Identify which policy events should trigger notifications (e.g. policy issued, payment failed, claim approved)
2. Create custom notification events on the Root dashboard (Dashboard → Notifications → Custom Events) — each event has a `key` and a template
3. Trigger notifications from lifecycle hooks using the `trigger_custom_notification_event` action
4. For programmatic triggers (e.g. inside `getApplication` or scheduled functions), use `root.notifications.triggerCustomEvent()`
5. For fully custom emails (dynamic content, no dashboard template), use `root.policies.sendMail()` with MJML markup
6. Test notifications in sandbox — they will appear in execution logs but won't send to real recipients
7. If creating new files, add them to `codeFileOrder` in `.root-config.json`
8. Run `/rp-dev` to push the draft

→ Notification actions are returned by lifecycle hooks — see `/dev-actions`
→ For the full SDK reference, see `/dev-sdk`
→ Run `/rp-test` to verify

---

## Reference: trigger via lifecycle hook action

Returned from any lifecycle hook or scheduled function. The dashboard template handles the content.

```js
const afterPolicyIssued = ({ policy, policyholder }) => {
  return [{
    name: 'trigger_custom_notification_event',
    custom_event_key: 'welcome_notification',
    custom_event_type: 'policy',       // policy | payment_method | payment | claim
    policy_id: policy.policy_id,
  }];
};
```

| `custom_event_type` | Required ID field |
|---|---|
| `policy` | `policy_id` |
| `payment_method` | `policy_id` |
| `payment` | `payment_id` |
| `claim` | `claim_id` |

## Reference: trigger via SDK (programmatic)

Use inside any hook or function — not limited to action-returning hooks.

```js
await root.notifications.triggerCustomEvent({
  customEventKey: 'payment_reminder',
  customEventType: 'policy',
  id: policy.policy_id,
});
```

## Reference: send custom MJML email

For fully custom emails where a dashboard template isn't suitable. Uses [MJML](https://mjml.io/) markup.

```js
await root.policies.sendMail({
  subject: 'Your policy schedule is ready',
  mjml: `
    <mjml>
      <mj-body>
        <mj-section>
          <mj-column>
            <mj-text>Hi ${policyholder.first_name},</mj-text>
            <mj-text>Your policy ${policy.policy_number} is now active.</mj-text>
          </mj-column>
        </mj-section>
      </mj-body>
    </mjml>
  `,
  to: { email: policyholder.email, name: policyholder.first_name },
  from: { email: 'support@company.com', name: 'Company Insurance' },
  policyId: policy.policy_id,  // links email to policy in dashboard
});
```

## Reference: common notification patterns

**Payment failure warning** (from `afterPaymentFailed`):
```js
const failedCount = (policy.module.failed_payment_count || 0) + 1;
if (failedCount >= 2) {
  return [{
    name: 'update_policy',
    data: { module: { ...policy.module, failed_payment_count: failedCount } },
  }, {
    name: 'trigger_custom_notification_event',
    custom_event_key: 'payment_failure_warning',
    custom_event_type: 'policy',
    policy_id: policy.policy_id,
  }];
}
```

**Claim decision notification** (from `afterClaimDecision`):
```js
const afterClaimDecision = ({ policy, policyholder, claim }) => {
  const eventKey = claim.approval_status === 'approved'
    ? 'claim_approved' : 'claim_declined';
  return [{
    name: 'trigger_custom_notification_event',
    custom_event_key: eventKey,
    custom_event_type: 'claim',
    claim_id: claim.claim_id,
  }];
};
```

**Policy anniversary** (from scheduled function):
```js
const anniversaryCheck = ({ policy, policyholder }) => {
  const anniversary = moment(policy.start_date).year(moment().year());
  const daysUntil = anniversary.diff(moment(), 'days');
  if (daysUntil === 30) {
    return [{
      name: 'trigger_custom_notification_event',
      custom_event_key: 'policy_anniversary_reminder',
      custom_event_type: 'policy',
      policy_id: policy.policy_id,
    }];
  }
  return [];
};
```
