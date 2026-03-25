# /rp-dev — Diff and Push a New Draft

Show what has changed locally compared to the latest draft on Root, then push a new draft.

## Arguments

Pass `--force` in `$ARGUMENTS` to skip the confirmation prompt and push immediately.

## Steps

1. **Show diff**
   ```bash
   rp diff
   ```
   Display the output clearly. If there are no changes, tell the user and stop — nothing to push.

2. **Confirm push**
   Unless `--force` is in `$ARGUMENTS`, ask the user: "Ready to push these changes as a new draft?"
   - If yes, continue
   - If no, stop here

3. **Push**
   ```bash
   rp push
   ```
   Display the output. A successful push creates a new draft version on Root.

4. **Confirm**
   After a successful push, remind the user:
   - Run `/rp-test` to verify the draft behaves correctly in sandbox
   - Run `/rp-publish` when ready to go live
   - Changes are NOT live yet — this is a draft
