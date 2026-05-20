# Proposal 07 — Schema reference: callout for columns analysts expect that don't exist

**Source feedback note (`feedback/2026-05-19.jsonl`):**
- `2026-05-19T09:11:38Z` (rule-missing) — `users` table has no `password_changed_at`, `mfa_method`, `mfa_enabled` columns; password-age and 2FA analysis cannot be done via the data adapter. Recommend Root API `/v1/users` as the alternative surface.

## Reason

`references/schema.md` already documents most of this (line 664 has the MFA note, line 662 documents `password_last_changed`). The remaining friction is **column naming convention mismatch**: the codebase convention is `*_at` for timestamp columns (e.g. `created_at`, `updated_at`, `last_logged_in_at`), so an agent searching the schema for "password change history" reaches for `grep password_changed_at references/schema.md` and finds nothing — even though `password_last_changed` exists.

The fix is a tiny "you might have looked for this" alias map in the users-table section so `grep` lands the agent on the right column.

## Current state

`references/schema.md:642-664`:

```markdown
### `users`
No `environment` column. Dashboard/API users — not policyholders.

| Column | Type | Notes |
|---|---|---|
| `id` | varchar | PK |
| ...
| `password_last_changed` | varchar | timestamp with tz stored as varchar; cast before arithmetic; NULL for ~42/51 users (field newly added, backfill incomplete) |

> No MFA columns — 2FA method and enforcement policy are not available in the data adapter. Source from Root Dashboard → Team or Root API `/v1/users`. `password_last_changed` and `last_logged_in` are now present but stored as varchar.
```

Good content already. The thing missing is greppability under the names an agent would type first.

## Proposed change

### `.agents/references/schema.md` — users section

Add a "Likely-searched-for but not present" mini-table immediately after the existing footnote callout:

```markdown
> No MFA columns — 2FA method and enforcement policy are not available in the data adapter. Source from Root Dashboard → Team or Root API `/v1/users`. `password_last_changed` and `last_logged_in` are now present but stored as varchar.

**Aliases / lookup helper.** If you're hunting for one of these and grep fails:

| You searched for | Actual column / source |
|---|---|
| `password_changed_at` | `password_last_changed` (varchar, see above) |
| `last_login_at`, `last_login` | `last_logged_in` (varchar) |
| `mfa_enabled`, `mfa_method`, `2fa_*` | Not in data adapter. Root API `/v1/users` |
| `password_strength`, `password_age_days` | Derive client-side from `password_last_changed`; raw strength signals not stored |
| `failed_login_count` | `login_attempts` (integer) |
```

Same shape can be applied to other tables as friction surfaces — but this proposal is scoped to `users` because that's where the observe note landed. Don't pre-emptively populate other tables; wait for signal.

## Notes / non-changes

- The existing MFA-not-here note stays — it's correct and useful.
- This is **doc-only**; no code change. Risk surface is zero; the worst case is the alias table going stale, which (a) is no worse than the rest of `schema.md` and (b) is detectable by `glue-describe.sh --has-column users password_changed_at` (always exits non-zero ⇒ alias stays valid).
- Pointing at the Root API as the alternative surface is the right routing — `/dev-sdk` and `tools/root-api.sh` already cover this path.

## Test

```bash
# Greppability — every "wrong" name should now appear in schema.md
for c in password_changed_at last_login_at last_login mfa_enabled mfa_method failed_login_count; do
  grep -q "$c" .agents/references/schema.md && echo "OK: $c" || echo "MISS: $c"
done
# All should print OK.

# Sanity: the actual columns are still findable
for c in password_last_changed last_logged_in login_attempts; do
  grep -q "$c" .agents/references/schema.md && echo "OK: $c"
done
```

Acceptance: an agent grepping the schema reference for any of the "likely searched" names lands in the right section and is routed either to the real column or to the Root API.
