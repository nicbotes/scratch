# Dev Skill: Billing Settings Configuration

Configure billing settings in `.root-config.json` — payment methods, frequency, currency, retry logic, pro-rata billing, and premium collection rules.

## Steps

1. Open `.root-config.json` and locate or create the `settings.billing` object
2. Set `billingFrequency` — `"monthly"` (most common), `"yearly"`, `"weekly"`, `"daily"`, or `"once_off"`
3. Set `currency` to the ISO 4217 code (e.g. `"ZAR"`, `"USD"`, `"GBP"`)
4. Set `clientStatementReference` — max 10 chars, appears on bank statements for debit orders
5. Configure `paymentMethodTypes` — enable the methods the product supports (debitOrders, card, eft, external)
6. If using debit orders, set `strategy` — `"same_day"`, `"debicheck"`, or `"best_effort"`
7. Configure `retryFailedPayments` — enable/disable, set days between retries and number of retries
8. Set `consecutiveFailedPaymentsAllowed` (default 4 if omitted) — failed retries count toward this
9. Configure `proRataBilling` for mid-cycle policy issuance
10. Set optional features as needed (see reference below)
11. Push with `/rp-dev`

→ Billing interacts with payment hooks — see `/dev-payment-hooks` for `afterPaymentFailed` logic
→ Lapse rules are in general settings — see `/dev-config`

---

## Reference: core billing settings

```json
{
  "billing": {
    "billingFrequency": "monthly",
    "currency": "ZAR",
    "clientStatementReference": "ACME",
    "paymentSubmissionLeadTime": 0,
    "billBeforeWeekendEnabled": false,
    "enableBillingOnSandbox": true
  }
}
```

## Reference: payment method types

```json
{
  "paymentMethodTypes": {
    "debitOrders": {
      "enabled": true,
      "naedoPoliciesInArrears": true,
      "strategy": "best_effort"
    },
    "card": { "enabled": false },
    "eft": { "enabled": false },
    "external": { "enabled": false, "createPayments": false }
  }
}
```

| Strategy | Type | Description |
|---|---|---|
| `same_day` | EFT | Submitted and actioned on payment date |
| `two_day` | EFT | Submitted 2 days before (deprecated) |
| `debicheck` | DebiCheck | Requires mandate; bank tracks for 5 days |
| `best_effort` | Hybrid | EFT normally, DebiCheck for arrears |

External with `createPayments: true` — platform generates payments for external provider to process.

## Reference: retry and failure settings

```json
{
  "retryFailedPayments": {
    "enabled": true,
    "daysBetweenRetries": 5,
    "numberOfRetries": 2
  },
  "consecutiveFailedPaymentsAllowed": 4
}
```
**Note**: Failed retries count toward `consecutiveFailedPaymentsAllowed` and toward lapse rules.

## Reference: pro-rata billing

```json
{
  "proRataBilling": {
    "enabled": true,
    "proRataBillingOnIssue": false,
    "minimumAmount": 0
  }
}
```
`proRataBillingOnIssue: true` = bill pro-rata on start date. `false` = bill with first premium.

## Reference: optional billing features

| Setting | Type | Default | Purpose |
|---|---|---|---|
| `minimumPaymentAmount` | `{ enabled, amountInCents }` | disabled | Minimum threshold for creating payments |
| `combineProRataAndPremium` | `{ enabled, daysBeforeBilling }` | enabled, 5 days | Merge pro-rata with first premium |
| `assumeSuccess` | `{ enabled, daysAfterPaymentDate }` | per payment type | Auto-mark payments as successful after N days |
| `disableDebitPremiums` | boolean | false | Don't debit premiums on schedule |
| `disableBillingDayAdjustments` | `{ enabled }` | disabled | Skip ledger adjustments on billing day change |
| `alwaysChargeMonthlyPremium` | `{ enabled }` | disabled | Create payment even when balance is zero/credit |
| `doNotBlockPaymentMethodFailureCodes` | `{ enabled, codes[] }` | disabled | Don't block payment method for specific failure codes |

`assumeSuccess` is set per payment method type (e.g. `debitOrders.assumeSuccess`). Only used if feature flag `use_assume_success_setting` is enabled.
