---
name: whoami
description: Resolve which API base + token the current shell is pointed at, and confirm connectivity. Use at session start, when switching projects, or whenever something feels off. Do NOT use for routine queries — orientation only.
---

# Skill: whoami

Confirms the framework's API credentials work and surfaces the identity the token resolves to (when the API exposes one).

## Steps

1. **Run:**
   ```bash
   bash .agents/tools/whoami.sh --endpoint /user        # GitHub
   bash .agents/tools/whoami.sh --endpoint /me          # many SaaS APIs
   bash .agents/tools/whoami.sh                         # no path: just hits API_BASE_URL
   ```
2. **Read the output:**
   - `API base:` confirms which API the session is pointed at.
   - `API hash:` is the 16-hex prefix used for committed paths (`regressions/<hash>/`, telemetry).
   - `Mode:` shows the PII compliance mode (`strict` / `standard` / `off`).
   - `Probe:` shows the HTTP status. 200 = good. 401/403 = token issue. 404 = endpoint wrong, but auth might still be fine.
   - `Identity:` (when present) shows the user/account the token resolves to.
3. **If the probe fails:**
   - 401/403: regenerate `API_TOKEN` per `references/sources/<name>.md`.
   - Connection error: confirm `API_BASE_URL` has no trailing slash and is reachable from this machine.
   - Missing var: `cat .agents/.env` — confirm `API_BASE_URL` and `API_TOKEN` are present and exported.

→ Next: `discover-api` (first contact with a source) or `land-data` (pull fresh data).
