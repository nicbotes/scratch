# /rp-logs — View and Summarise Execution Logs

Fetch the most recent execution logs for the product module from Root.

## Steps

1. **Fetch logs**
   ```bash
   rp logs
   ```
   Display the raw log output.

2. **Analyse and summarise**
   After displaying the logs, provide a summary:
   - Count of successful vs failed executions (if distinguishable)
   - Any `Error` or `Exception` messages — quote them verbatim and indicate which workflow step they came from (quote, application, alteration, etc.)
   - Any unexpected `undefined` values or type errors
   - Patterns: e.g. "failing consistently on the alteration hook" or "only failing for specific input values"

3. **Suggest next steps**
   Based on what you find:
   - If errors relate to specific code — point the user to the relevant file/function
   - If errors are intermittent — suggest adding `console.log` statements and re-running `/rp-test`
   - If logs are clean — confirm that and suggest the user can proceed to `/rp-publish`
