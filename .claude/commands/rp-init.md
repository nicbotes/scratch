# /rp-init — Initialise a New Product Module

Create a brand-new product module on Root and clone it locally.

## Steps

1. **Pre-check**
   Run `/rp-setup` logic to confirm `rp` CLI is installed. Auth is not required for init — skip that check.

2. **Run init** — choose one of:

   **Option A: Interactive**
   ```bash
   rp init
   ```
   This command is interactive — it will prompt for a module name and type. Let the user respond to those prompts directly.

   **Option B: Non-interactive (preferred for automation)**
   ```bash
   rp create <api-key> "<Module Display Name>" <module_key>
   ```
   - `<api-key>` — sandbox API key (from `.root-auth` or provided by user)
   - `"<Module Display Name>"` — human-readable name (quote if it contains spaces)
   - `<module_key>` — snake_case identifier for the module

   This creates the module on Root **and** scaffolds the local directory in one step.

3. **Confirm result**
   Once complete, list the newly created directory structure so the user can see what was scaffolded:
   ```bash
   find . -not -path './.git/*' | sort
   ```

4. **Next steps**
   Remind the user to:
   - Add their API key to `.root-auth` (see `/rp-setup`)
   - Add `.root-auth` to `.gitignore`
   - Run `/rp-dev` when they're ready to push their first draft

---

→ **CRITICAL**: Module keys are **globally unique across all Root organisations**. If `rp create` fails with `conflict_error` ("already exists"), the key is taken by another org — even if you can't see it. Choose a different key (e.g. append `_v2`). Note that `rp clone` will also fail with `not_found_error` for a module owned by a different org.
