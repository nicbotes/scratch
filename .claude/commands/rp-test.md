# /rp-test — Run Tests and Sandbox Smoke Test

Run unit tests and optionally create a test policy in sandbox to verify end-to-end behaviour.

## Arguments

- `watch` — run unit tests in watch mode (re-runs on file changes)
- `sandbox` — also create a sandbox quote/application/policy after unit tests pass
- `sandbox-only` — skip unit tests, just create a sandbox policy

## Steps

1. **Unit tests** (unless `sandbox-only` in `$ARGUMENTS`)

   If `watch` is in `$ARGUMENTS`:
   ```bash
   rp test -w
   ```
   Otherwise:
   ```bash
   rp test
   ```
   - Tests live in `code/unit-tests/` and use the Chai assertion library
   - Test files are appended to product module code and executed together
   - Display pass/fail results. If any tests fail, stop and report the failures clearly

2. **Sandbox policy creation** (if `sandbox` or `sandbox-only` in `$ARGUMENTS`, or if user confirms)

   If unit tests passed (or were skipped), offer to create a test policy:
   ```bash
   rp create
   ```
   This creates a quote, application, and policy in sandbox using the payloads in `./payloads/`.
   - Requires payloads to exist in `./payloads/` directory
   - Uses the current **live** product module version (not the draft)
   - Display the resulting quote/application/policy output

3. **Summary**
   Report overall pass/fail status. If anything failed, suggest checking `/rp-logs` for execution details.
