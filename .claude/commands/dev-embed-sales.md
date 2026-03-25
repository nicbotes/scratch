# Dev Skill: Embed Sales Flow (Quote to Issue)

Configure the white-label, mobile-responsive customer-facing embed — the quote-to-policy issuing journey. Embed Sales runs as an iframe or standalone site, driven by your quote/application schemas and `embed-config.json`.

## Steps

1. Ensure `/dev-quote-hook`, `/dev-application-hook`, and `/dev-schema` are complete — schemas drive the embed forms
2. Create `workflows/embed/embed-config.json` with the top-level structure (see reference below)
3. Configure `styles` — brand colors, fonts, border radius
4. Configure `settings` — support contact, session persistence, analytics
5. Configure `landing` — entry page with marketing copy, optional video, CTA button
6. Configure `quote` — description, optional screening questions, optional consent disclaimer
7. Configure `personalDetails` — contact types, optional skip-on-prefill, optional address autocomplete
8. Configure `application` — title and description (form fields come from application schema)
9. Configure `beneficiaries` if the product supports them
10. Configure `payment` — summary with Handlebars templating, consent items, declaration, billing day toggle
11. Configure `confirmation` — success page copy, redirect URL, claim link
12. Optionally configure compliance steps: `prePersonalDetailsCompliance` and `prePaymentCompliance` with markdown content in `documents/`
13. Configure `inputFields.personalDetails` for custom labels and prefill behavior
14. Push with `/rp-dev` and test in the sandbox embed URL

→ For post-issue self-service, see `/dev-embed-manage`
→ Schemas drive embed forms — see `/dev-schema`

---

## Reference: top-level embed-config.json structure

```json
{
  "styles": {},
  "settings": {},
  "header": {},
  "footer": {},
  "landing": {},
  "quote": {},
  "prePersonalDetailsCompliance": {},
  "personalDetails": {},
  "application": {},
  "beneficiaries": {},
  "prePaymentCompliance": {},
  "payment": {},
  "confirmation": {},
  "inputFields": {},
  "management": {}
}
```

## Reference: styles (brand theming)

```json
{
  "styles": {
    "colors": {
      "primary": "#240E8B",
      "highlight": "#FC64B1",
      "dark": "#000000",
      "light": "#FFFFFF",
      "success": "#1fc881",
      "warning": "#FC64B1",
      "error": "#ff2b38",
      "disabled": "#CDD4DE",
      "backgroundHighlight": "rgba(245, 247, 252, 1)",
      "border": "rgba(0, 0, 0, 0.125)"
    },
    "fontFamily": { "title": "Lato", "body": "Lato" },
    "fontSize": { "title": "40px", "subTitle": "22px", "body": "16px", "button": "14px", "subscript": "8px" },
    "borderRadius": { "button": "8px" }
  }
}
```

## Reference: settings (global config)

```json
{
  "settings": {
    "issuingFlowStartingStep": "default",
    "defaultCountryCodeFromBrowser": true,
    "supportType": "email",
    "supportEmail": "support@company.com",
    "enableSessionPersistence": true,
    "mixpanelProjectToken": "<token>"
  }
}
```

`issuingFlowStartingStep`: `"default"` (landing → quote) or `"personalDetails"` (personal details first).

## Reference: landing page

```json
{
  "landing": {
    "wording": {
      "title": "Get Covered",
      "subTitle": "From R149 p/m",
      "descriptionBullets": ["24/7 claims support", "Cover from day one"],
      "createQuoteButton": "Get a quote"
    },
    "images": { "background": "https://cdn.example.com/hero.svg" },
    "displayOptionalSections": { "displayLandingPage": true, "descriptionBullets": true }
  }
}
```

Set `displayLandingPage: false` to skip straight to quote.

## Reference: quote step

```json
{
  "quote": {
    "wording": {
      "description": "Complete the steps below to get your quote",
      "premiumTitle": "Monthly premium",
      "callToAction": "Sign me up!",
      "screeningQuestions": [
        { "key": "declined_before", "header": "Pre-screening", "question": "Have you been declined cover in the last 5 years?" }
      ],
      "consentDisclaimer": { "title": "Consent", "consentItems": ["I consent to data processing."] }
    },
    "links": { "supportType": "email", "supportEmail": "help@company.com" },
    "displayOptionalSections": { "screeningQuestions": true, "consentDisclaimer": true }
  }
}
```

Split quote into multiple pages: add `sectionIndex: number` on quote schema components.

## Reference: payment step (Handlebars summary)

```json
{
  "payment": {
    "wording": {
      "title": "Payment",
      "summary": [
        { "label": "Cover amount", "content": "{{formatCurrency application.sum_assured application.currency}}" },
        { "label": "Premium", "content": "{{formatCurrency application.monthly_premium application.currency}} / month" }
      ],
      "consentItems": ["The information I provided is true and correct."],
      "declaration": "By proceeding you agree to the terms and conditions."
    },
    "displayOptionalSections": { "displayPaymentMethod": true, "billingDay": true }
  }
}
```

## Reference: prefill via URL query parameters

| Parameter | Purpose |
|---|---|
| `quote_values` | JSON string of quote schema fields |
| `personal_details_values` | JSON string of policyholder fields |
| `application_values` | JSON string of application fields |
| `payment_values` | JSON string of payment/debit order fields |

```
?quote_values={"type":"my_product","age":32,"cover_amount":50000000}
&personal_details_values={"first_name":"John","last_name":"Doe","email":"john@example.com"}
```

## Reference: input field prefill actions

Control what happens when a field is prefilled:

| Action | Behavior |
|---|---|
| `"none"` | Show and allow editing (default) |
| `"hidden"` | Hide the field completely |
| `"disabled"` | Show but read-only |

```json
{
  "inputFields": {
    "personalDetails": {
      "email": { "label": "Email address", "prefillAction": "hidden" },
      "dateOfBirth": { "label": "Date of birth", "prefillAction": "disabled" }
    }
  }
}
```
