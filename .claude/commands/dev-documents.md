# Dev Skill: Policy Document Templates

Build or update HTML document templates that Root renders to PDF. Every module requires a policy schedule and terms document.

## Steps

1. Read existing templates in `documents/` (if any)
2. Identify what data from `policy.module` should appear in each document
3. Create or update `documents/policy-schedule.html` using Handlebars for dynamic fields
4. Create or update `documents/terms.html` (usually static, but can include policy-specific terms)
5. Use Root's custom helpers (`{{currency}}`, `{{date}}`) for formatting — see reference below
6. Preview with `/rp-render --merge` using test data from `sandbox/merge-vars.json`
7. Iterate until layout and data are correct
8. Run `/rp-dev` to push the draft

→ Use `/rp-render` to preview output as PDF without pushing

---

## Reference: required and optional documents

| File | Required | Purpose |
|---|---|---|
| `documents/policy-schedule.html` | yes | Issued to policyholder on issuance |
| `documents/terms.html` | yes | Terms and conditions |
| `documents/welcome-letter.html` | no | Welcome communication |
| `documents/anniversary-letter.html` | no | Annual renewal communication |

## Reference: Handlebars syntax

```html
{{policyholder.first_name}}              output a value
{{#if policy.module.has_rider}} ... {{/if}}    conditional
{{#each policy.module.beneficiaries}} {{this.first_name}} {{/each}}   loop
```

## Reference: available merge variables

```
{{policyholder.first_name}}, {{policyholder.last_name}}
{{policyholder.email}}, {{policyholder.cellphone}}, {{policyholder.id_number}}

{{policy.policy_number}}, {{policy.package_name}}, {{policy.status}}
{{policy.sum_assured}}, {{policy.monthly_premium}}   ← in cents, use {{currency}} helper
{{policy.start_date}}                                 ← ISO string, use {{date}} helper
{{policy.module.*}}                                   ← your custom data
```

## Reference: Root's custom Handlebars helpers

```html
{{currency policy.monthly_premium}}              → R 1,250.00
{{date policy.start_date 'DD MMMM YYYY'}}        → 01 January 2025
{{upper policyholder.last_name}}                 → SMITH
{{lower policyholder.first_name}}                → john
```

Full helper reference: https://docs.rootplatform.com/docs/handlebars-helper-reference

## Reference: minimal policy schedule structure

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; font-size: 12pt; padding: 40px; }
    table { width: 100%; border-collapse: collapse; }
    td, th { padding: 8px; border: 1px solid #ddd; }
    .page-break { page-break-after: always; }
  </style>
</head>
<body>
  <h1>Policy Schedule</h1>
  <p>Policy Number: {{policy.policy_number}}</p>
  <table>
    <tr><td>Policyholder</td><td>{{policyholder.first_name}} {{policyholder.last_name}}</td></tr>
    <tr><td>Cover Amount</td><td>{{currency policy.sum_assured}}</td></tr>
    <tr><td>Monthly Premium</td><td>{{currency policy.monthly_premium}}</td></tr>
    <tr><td>Start Date</td><td>{{date policy.start_date 'DD MMMM YYYY'}}</td></tr>
  </table>
</body>
</html>
```
