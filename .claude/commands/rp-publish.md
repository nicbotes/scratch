# /rp-publish — Publish Draft to Live

Publish the current draft version of the product module to live. This affects real policies.

## Arguments

Must include `confirm` in `$ARGUMENTS` to proceed. This is a safety gate.

## Steps

1. **Safety gate**
   If `$ARGUMENTS` does not contain `confirm`:
   ```
   ⚠️  This will publish your draft to LIVE. All policies issued going forward will use this version.

   To proceed, run: /rp-publish confirm
   ```
   Stop here.

2. **Show diff before publishing**
   ```bash
   rp diff
   ```
   Display the changes that are about to go live. Ask the user: "These changes will be published. Are you sure?"
   - If they say no, stop
   - If they say yes, continue

3. **Publish**
   ```bash
   rp publish --force
   ```
   The `--force` flag skips the interactive confirmation in the CLI itself (we handled confirmation above).

4. **Confirm**
   Display the result. On success:
   - Confirm the version number that was published
   - Remind the user that existing policies reference the version they were created under — publishing a new version does not retroactively change them
   - Suggest running `/rp-logs` over the next few minutes to monitor for any runtime errors on the new version
