# Delivery Workflow Notes

## Branch hygiene checklist

1. **Create or switch to the feature branch** before touching files.
2. **Stage, commit, and push** every meaningful change set:
   - `git add <files>`
   - `git commit -m "concise summary"`
   - `git push origin <branch>`
3. **Verify the remote branch** actually has the commits (`git status -sb` should be clean; GitHub should show the latest hash).
4. **Only share preview links after the push** so reviewers aren’t staring at stale content.

## What happened (2026-03-20)

- I created branch `demo` and edited the funeral product section but forgot to commit/push.
- Shared links pointed to GitHub where nothing new existed, wasting reviewer time.
- Fixed by staging `index.html`, `styles.css`, and `script.js`, committing as `"Add funeral product prototype section"`, then pushing `demo`.
- Added this checklist so the push step is never skipped again.
