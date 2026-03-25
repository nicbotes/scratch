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

   **Non-interactive (preferred for automation):**
   ```bash
   rp push -f
   ```
   The `-f` flag skips the interactive diff confirmation and pushes immediately.

   **Fallback** (if `-f` is unavailable or you need to see the diff first):
   ```bash
   echo 'y' | rp push
   ```

   → **CRITICAL**: Plain `rp push` (without `-f` or piped input) shows a diff and waits for `y/n` confirmation, which **blocks** non-interactive/automated workflows. Always use one of the above forms.

   Display the output. A successful push creates a new draft version on Root.

4. **Confirm**
   After a successful push, remind the user:
   - Run `/rp-test` to verify the draft behaves correctly in sandbox
   - Run `/rp-publish` when ready to go live
   - Changes are NOT live yet — this is a draft
