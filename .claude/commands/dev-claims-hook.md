# Dev Skill: Claims Lifecycle Hooks

Implement claims-related lifecycle hooks — responding to claim block updates, assessment decisions, and claim lifecycle events. Claims hooks follow the same action-return pattern as other lifecycle hooks.

## Steps

1. Read existing lifecycle hooks in `code/` for any claim-related hooks
2. Understand the claims flow: open claim → link policy → update blocks → send to review → decision → acknowledge → close
3. Implement `afterPolicyLinkedToClaim({ policy, policyholder, claim })` if logic is needed when a claim is linked
4. Implement `afterClaimBlockUpdated({ block_key, policy, policyholder, claim })` for block change reactions
5. **WARNING**: `afterClaimBlockUpdated` fires on EVERY block update, including those caused by your own actions — guard against infinite loops
6. Implement `beforeClaimSentToReview({ policy, policyholder, claim })` to validate or enrich before review — throw to prevent
7. Implement `afterClaimDecision({ policy, policyholder, claim })` — check `claim.approval_status` for the decision type
8. Implement `afterClaimDecisionAcknowledged` and `afterClaimClosed` as needed
9. If creating new files, add them to `codeFileOrder` in `.root-config.json`
10. Run `/rp-dev` to push the draft

→ Claim hooks return actions — see `/dev-actions` for the full reference
→ Use `update_claim_module_data` action to update claim-specific data
→ Run `/rp-test` to verify

---

## Reference: claims hook signatures

All claim hooks receive `{ policy, policyholder, claim }`. `afterClaimBlockUpdated` also receives `block_key`.

| Hook | Trigger | Can prevent? |
|---|---|---|
| `afterPolicyLinkedToClaim` | Policy linked to a claim | No |
| `afterClaimBlockUpdated` | Any claim block state change | No |
| `beforeClaimSentToReview` | Before claim goes to assessor | Yes (throw) |
| `afterClaimSentToReview` | After claim sent to assessor | No |
| `beforeClaimSentToCapture` | Before claim sent to capture | Yes (throw) |
| `afterClaimSentToCapture` | After claim sent to capture | No |
| `afterClaimDecision` | Assessor approves/repudiates/goodwill/no_claim | No |
| `afterClaimDecisionAcknowledged` | Supervisor acknowledges decision | No |
| `afterClaimClosed` | Claim is closed | No |

## Reference: infinite loop guard pattern

```js
const afterClaimBlockUpdated = ({ block_key, policy, policyholder, claim }) => {
  // CRITICAL: Only act on specific blocks to avoid infinite loops
  if (block_key !== 'loss_details') return [];

  // Only act if the block hasn't already been processed
  if (claim.module && claim.module.loss_details_processed) return [];

  return [{
    name: 'update_claim_module_data',
    data: { loss_details_processed: true, flagged_for_review: true },
  }];
};
```

## Reference: afterClaimDecision pattern

```js
const afterClaimDecision = ({ policy, policyholder, claim }) => {
  // claim.approval_status: 'approved' | 'repudiated' | 'goodwill' | 'no_claim'
  switch (claim.approval_status) {
    case 'approved':
      return [{
        name: 'trigger_custom_notification_event',
        custom_event_key: 'claim_approved',
        custom_event_type: 'claim',
        claim_id: claim.claim_id,
      }];
    case 'repudiated':
      return [{
        name: 'trigger_custom_notification_event',
        custom_event_key: 'claim_repudiated',
        custom_event_type: 'claim',
        claim_id: claim.claim_id,
      }];
    default:
      return [];
  }
};
```

## Reference: beforeClaimSentToReview validation

```js
const beforeClaimSentToReview = ({ policy, policyholder, claim }) => {
  // Throw to prevent the claim from being sent to review
  if (policy.status !== 'active') {
    throw new Error('Claims can only be reviewed for active policies');
  }
  return [];
};
```
