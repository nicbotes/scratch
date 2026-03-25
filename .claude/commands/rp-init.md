# /rp-init — Initialise a New Product Module

Create a brand-new product module on Root and clone it locally.

## Steps

1. **Pre-check**
   Run `/rp-setup` logic to confirm `rp` CLI is installed. Auth is not required for init — skip that check.

2. **Run init**
   ```bash
   rp init
   ```
   This command is interactive — it will prompt for a module name and type. Let the user respond to those prompts directly.

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
