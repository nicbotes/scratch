# Dev Skill: Product Settings Configuration

Configure `.root-config.json` general product settings — scheme type, policyholder rules, activation events, lapse/NTU rules, cooling-off/waiting periods, beneficiaries, documents, and hook registration.

## Steps

1. Read existing `.root-config.json` in the product module directory
2. Set `policySchemeType` — `"individual"` for personal policies, `"group"` for group schemes
3. Set `dashboardIssuingEnabled` to `true` if policies will be issued via the Root dashboard
4. Configure `policyholder` settings — which identity types are allowed, required fields
5. Set `activatePoliciesOnEvent` — when should a policy become active?
6. Configure `beneficiaries` (object with min/max) or set to `null` to disable
7. Configure `gracePeriod.lapseOn` — set lapse rules or `null` to disable each rule type
8. Set not-taken-up rules via `notTakenUpEnabled` (boolean) or `notTakenUp` (object with `failedPaymentsBeforeNTU`)
9. Configure `coolingOffPeriod` and `waitingPeriod` — set `theFullPolicy` to `null` to disable each
10. Configure `policyDocuments` array, `welcomeLetterEnabled`, and `policyAnniversaryNotification`
11. Register `alterationHooks` and `scheduledFunctions` arrays if the product uses them
12. Register `fulfillmentTypes` if claims have fulfillment workflows
13. Push with `/rp-dev`

→ Run `/dev-billing` next to configure billing settings
→ **CRITICAL**: All money amounts in config are integers in cents. R100.00 = `10000`.

---

## Reference: top-level required keys

```json
{
  "settings": { "..." },
  "alterationHooks": [],
  "scheduledFunctions": [],
  "fulfillmentTypes": []
}
```

## Reference: activation and scheme type

| Setting | Values |
|---|---|
| `policySchemeType` | `"individual"` \| `"group"` |
| `activatePoliciesOnEvent` | `"policy_issued"` \| `"payment_method_assigned"` \| `"first_successful_payment"` \| `"none"` |
| `dashboardIssuingEnabled` | boolean |
| `canReactivatePolicies` | boolean |
| `canRequote` | boolean (deprecated — use alteration hooks) |
| `defaultStatus` | `"pending"` \| `"pending_initial_payment"` |

## Reference: policyholder settings

```json
{
  "policyholder": {
    "companiesAllowed": false,
    "individualsAllowed": true,
    "individualsIdAllowed": true,
    "individualsPassportAllowed": true,
    "individualsEmailAllowed": false,
    "individualsCellphoneAllowed": false,
    "individualsCustomIdAllowed": false,
    "customIdName": "Driving License",
    "idCountry": "ZA",
    "individualPolicyholderFields": {
      "dateOfBirth": { "required": true },
      "gender": { "hidden": true },
      "address": { "suburb": { "required": false } }
    }
  }
}
```

## Reference: beneficiaries

```json
{ "beneficiaries": { "makePolicyholderABeneficiary": true, "min": 1, "max": 5 } }
```
Set to `null` to disable beneficiaries entirely.

## Reference: grace period and lapse rules

Four rule types — set any to `null` to disable:

```json
{
  "gracePeriod": {
    "lapseOn": {
      "afterFirstMissedPayment": { "period": 15, "periodType": "days" },
      "consecutiveMissedPayments": { "number": 3 },
      "missedPaymentsOverPolicyTerm": { "number": 10 },
      "missedPaymentsWithinPeriod": { "number": 4, "period": 6, "periodType": "months" }
    },
    "lapseExclusionRules": {
      "lapsePolicyWithProcessingPayment": false,
      "arrearsThreshold": { "enabled": false, "thresholdInCents": "1000" },
      "excludeArrearsFromLapseCalculation": false
    }
  }
}
```

## Reference: NTU, cooling-off, waiting period

```json
{
  "notTakenUp": { "enabled": true, "failedPaymentsBeforeNTU": 1 },
  "coolingOffPeriod": { "applyTo": { "theFullPolicy": { "period": 1, "periodType": "months", "refundType": "all_premiums" } } },
  "waitingPeriod": { "applyTo": { "theFullPolicy": { "period": 30, "periodType": "days" } } }
}
```
Set `theFullPolicy` to `null` to disable cooling-off or waiting period.

## Reference: policy documents

```json
{
  "welcomeLetterEnabled": true,
  "policyAnniversaryNotification": { "daysBeforeToSend": 30 },
  "policyDocuments": [
    { "type": "terms" },
    { "type": "certificate", "enabled": true },
    { "type": "supplementary_terms", "supplementaryTermsType": "additional-terms", "fileName": "additional_terms" }
  ]
}
```
Types: `policy_schedule`, `terms`, `welcome_letter`, `policy_anniversary`, `certificate`, `supplementary_terms`.

## Reference: alteration hooks and scheduled functions registration

```json
{
  "alterationHooks": [
    { "key": "update_cover", "name": "Update Cover Amount" }
  ],
  "scheduledFunctions": [
    {
      "functionName": "applyAnnualIncrease",
      "policyStatuses": ["active"],
      "frequency": { "type": "yearly", "timeOfDay": "04:00", "dayOfMonth": 1, "monthOfYear": "january" }
    }
  ]
}
```
Frequency types: `daily`, `weekly` (+dayOfWeek), `monthly` (+dayOfMonth), `yearly` (+dayOfMonth, monthOfYear). Time: `H:00` or `H:30` only.

## Reference: fulfillment types

```json
{
  "fulfillmentTypes": [
    {
      "key": "bank_transfer",
      "label": "Bank Transfer",
      "fulfillmentData": {
        "account_number": { "label": "Account Number", "valueType": "string" }
      }
    }
  ]
}
```
