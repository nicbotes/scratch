# Dev Skill: Embed Management (Policy Self-Service)

Configure the Embed Management flow — authenticated policy self-service for policyholders to view policy details, manage beneficiaries, update payment methods, trigger alterations, and initiate claims.

## Steps

1. Ensure the Sales embed is configured first (`/dev-embed-sales`) — Management builds on the same `embed-config.json`
2. Add or update the `management` section in `workflows/embed/embed-config.json`
3. Configure `management.policyDetails` — policy summary with Handlebars, alteration hook toggles, cancellation
4. Configure `management.beneficiaries` if the product supports post-issue beneficiary management
5. Configure `management.payment` — allow editing payment method and/or billing day
6. Configure `management.claim` — claim instructions, contact number, and optional CTA link
7. Optionally configure `management.policyView` for an overview landing page within management
8. Optionally configure `management.personalDetails` for policyholder detail editing
9. Configure `inputFields.management` for field labels and prefill actions in management views
10. Push with `/rp-dev` and test via the sandbox management URL

→ Alteration hooks shown in management must be registered in `.root-config.json` — see `/dev-config`
→ For the quote-to-issue flow, see `/dev-embed-sales`

---

## Reference: management section structure

All sections are nested under `management` in `embed-config.json`. Each section follows the pattern: `wording`, `images`, `links`, `displayOptionalSections`.

```json
{
  "management": {
    "policyDetails": {},
    "beneficiaries": {},
    "payment": {},
    "claim": {},
    "policyView": {},
    "personalDetails": {}
  }
}
```

## Reference: policyDetails (summary + alterations)

```json
{
  "policyDetails": {
    "wording": {
      "title": "Policy details",
      "description": "Your current policy information",
      "summary": [
        { "label": "Cover amount", "content": "{{formatCurrency policy.sum_assured policy.currency}}" },
        { "label": "Monthly premium", "content": "{{formatCurrency policy.monthly_premium policy.currency}}" },
        { "label": "Status", "content": "{{policy.status}}" }
      ]
    },
    "links": { "exitRedirect": "https://myapp.com/dashboard" },
    "displayOptionalSections": {
      "alterationHooks": [
        { "key": "update_cover", "enabled": true },
        { "key": "update_beneficiaries", "enabled": true }
      ]
    }
  }
}
```

Policy status badge colors are set via `styles.colors.policyStatusActive`, `policyStatusLapsed`, etc.

## Reference: beneficiaries (post-issue management)

```json
{
  "beneficiaries": {
    "wording": { "title": "Beneficiaries", "description": "Manage your beneficiaries" },
    "links": { "exitRedirect": "https://myapp.com/dashboard" },
    "displayOptionalSections": { "readonlyView": false }
  }
}
```

Set `readonlyView: true` to display beneficiaries without allowing edits.

## Reference: payment (update method + billing day)

```json
{
  "payment": {
    "wording": { "title": "Payment details", "description": "Update your payment method" },
    "links": { "exitRedirect": "https://myapp.com/dashboard" },
    "displayOptionalSections": {
      "editPaymentMethod": true,
      "viewPaymentMethod": true,
      "editBillingDay": true
    }
  }
}
```

## Reference: claim (instructions + CTA)

```json
{
  "claim": {
    "wording": {
      "title": "Claims",
      "description": "To submit a claim, please contact us or fill out the online form.",
      "contactNumber": "0800 123 456",
      "callToAction": "Submit a claim"
    },
    "links": {
      "openClaim": "https://myapp.com/claims",
      "exitRedirect": "https://myapp.com/dashboard"
    },
    "displayOptionalSections": {
      "displayClaimSection": true,
      "contactNumber": true,
      "callToAction": true
    }
  }
}
```

## Reference: management input field labels

```json
{
  "inputFields": {
    "management": {
      "personalDetails": {
        "email": { "label": "Email address", "prefillAction": "disabled" },
        "cellphone": { "label": "Phone number", "prefillAction": "none" }
      },
      "beneficiaries": {
        "firstName": { "label": "First name", "prefillAction": "none" },
        "lastName": { "label": "Last name", "prefillAction": "none" }
      }
    }
  }
}
```

Management beneficiary fields support `prefillAction` (unlike Sales beneficiary fields which are label-only).
