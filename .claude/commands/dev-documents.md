# Dev Skill: Policy Document Templates

Create or update policy document templates. Documents are HTML files with Handlebars templating that Root converts to PDFs. Every product module requires at minimum a **policy schedule** and **terms document**.

## Required Documents

| Document | Purpose |
|---|---|
| `documents/policy-schedule.html` | Issued to policyholder on issuance; contains policy details |
| `documents/terms.html` | Terms and conditions |

## Optional Documents

| Document | Purpose |
|---|---|
| `documents/welcome-letter.html` | Welcome communication on issuance |
| `documents/anniversary-letter.html` | Annual renewal communication |

## Handlebars Basics

Handlebars injects dynamic data into HTML at render time.

**Output a value:**
```html
<p>Hello, {{policyholder.first_name}} {{policyholder.last_name}}</p>
```

**Conditionals:**
```html
{{#if policy.module.has_rider}}
  <p>Your policy includes the additional rider benefit.</p>
{{/if}}
```

**Loops:**
```html
{{#each policy.module.beneficiaries}}
  <tr>
    <td>{{this.first_name}} {{this.last_name}}</td>
    <td>{{this.percentage}}%</td>
  </tr>
{{/each}}
```

**Else:**
```html
{{#if policy.module.beneficiaries}}
  {{! show beneficiary table }}
{{else}}
  <p>No beneficiaries nominated.</p>
{{/if}}
```

## Available Merge Variables

**Policyholder:**
```
{{policyholder.first_name}}
{{policyholder.last_name}}
{{policyholder.email}}
{{policyholder.cellphone}}
{{policyholder.id_number}}
{{policyholder.date_of_birth}}
```

**Policy:**
```
{{policy.policy_number}}
{{policy.package_name}}
{{policy.sum_assured}}          ← in cents
{{policy.monthly_premium}}      ← in cents
{{policy.start_date}}
{{policy.status}}
{{policy.module.*}}             ← your custom module data
```

**Custom module data:**
```
{{policy.module.cover_amount}}
{{policy.module.beneficiaries}}
{{policy.module.age_at_inception}}
```

## Root's Custom Handlebars Helpers

Root extends Handlebars 4.0.12 with helpers for formatting:

```html
{{currency policy.monthly_premium}}       ← formats cents as R 1,250.00
{{date policy.start_date 'DD MMMM YYYY'}} ← formats ISO date
{{upper policyholder.last_name}}          ← UPPERCASE
{{lower policyholder.first_name}}         ← lowercase
```

Refer to the full helper reference at: https://docs.rootplatform.com/docs/handlebars-helper-reference

## HTML Structure

Documents are rendered to A4 PDF. Use print-friendly CSS:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body {
      font-family: Arial, sans-serif;
      font-size: 12pt;
      color: #333;
      margin: 0;
      padding: 40px;
    }
    .header {
      border-bottom: 2px solid #000;
      margin-bottom: 24px;
      padding-bottom: 12px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    td, th {
      padding: 8px;
      border: 1px solid #ddd;
    }
    @media print {
      .page-break { page-break-after: always; }
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>Policy Schedule</h1>
    <p>Policy Number: {{policy.policy_number}}</p>
  </div>

  <table>
    <tr>
      <td>Policyholder</td>
      <td>{{policyholder.first_name}} {{policyholder.last_name}}</td>
    </tr>
    <tr>
      <td>Cover Amount</td>
      <td>{{currency policy.sum_assured}}</td>
    </tr>
    <tr>
      <td>Monthly Premium</td>
      <td>{{currency policy.monthly_premium}}</td>
    </tr>
    <tr>
      <td>Start Date</td>
      <td>{{date policy.start_date 'DD MMMM YYYY'}}</td>
    </tr>
  </table>
</body>
</html>
```

## Testing Document Rendering

Use `/rp-render` to compile and preview as PDF locally:
- With merge vars from `sandbox/merge-vars.json`: `/rp-render --merge`
- With a real sandbox policyholder: `/rp-render --policyholder <id>`

## Steps

1. Read existing document template files (if any)
2. Identify all data from `policy.module` that should appear in documents
3. Create or update the HTML templates using Handlebars for dynamic data
4. Use Root's custom helpers for currency and date formatting
5. Use `/rp-render` to preview the output as PDF
6. Iterate until the layout and data are correct
7. Run `/rp-dev` to push the draft
