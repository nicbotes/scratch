# /rp-clone — Clone an Existing Product Module

Fetch the latest draft of an existing product module from Root and set it up locally.

## Arguments

`$ARGUMENTS` may contain a module identifier or name. Pass it through if provided.

## Steps

1. **Pre-check**
   Confirm `rp` CLI is installed (`rp help`). If not, tell the user to run `npm install -g @rootplatform/cli`.

2. **Run clone**
   ```bash
   rp clone
   ```
   Or if a module name/ID was provided in `$ARGUMENTS`:
   ```bash
   rp clone $ARGUMENTS
   ```
   This is typically only run once per module — it sets up the local directory.

3. **Verify auth**
   After cloning, check that `.root-auth` exists (or prompt the user to create it). The clone creates `.root-config.json` but not `.root-auth`.

4. **Show structure**
   Display the cloned directory structure so the user can see what was fetched.

5. **Next steps**
   The user can now:
   - Edit code in `code/`
   - Run `/rp-dev` to push changes
   - Run `/rp-test` to run unit tests
