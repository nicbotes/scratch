# /rp-render — Render Document Templates to PDF

Compile HTML document templates into PDF files locally.

## Arguments

`$ARGUMENTS` may contain:
- `merge` — execute Handlebars templating using `./sandbox/merge-vars.json`
- `policyholder <id>` — fetch merge variables for a specific sandbox policyholder by ID

## Steps

1. **Determine flags**
   Parse `$ARGUMENTS`:
   - If it contains `merge` → add `--merge` flag
   - If it contains `policyholder` followed by an ID → add `--policyholder <id>` flag
   - Both can be combined

2. **Run render**

   No merge vars:
   ```bash
   rp render
   ```
   With merge vars from file:
   ```bash
   rp render --merge
   ```
   With merge vars from a specific policyholder:
   ```bash
   rp render --policyholder <id>
   ```

3. **Show output**
   PDFs are written to `./sandbox/output/`. List the generated files and their sizes.

4. **Context**
   Document templates are HTML files in the `documents/` directory using [Handlebars](https://handlebarsjs.com/) syntax. Merge variables populate dynamic fields (e.g. policyholder name, policy number, premium). Use `./sandbox/merge-vars.json` to provide test data.
