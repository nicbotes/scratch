# /rp-setup — Verify Root Platform Environment

Check that everything is in place before starting work on a product module.

## Steps

1. **Check CLI is installed**
   ```bash
   rp help
   ```
   If this fails, tell the user to run: `npm install -g @rootplatform/cli`

2. **Check working directory**
   Confirm the current directory contains a `.root-config.json` file. If not, ask the user which product module directory to work in, or suggest running `/rp-init` or `/rp-clone` first.

3. **Check auth**
   Check that a `.root-auth` file exists in the current directory and contains a line matching `ROOT_API_KEY=`. Do NOT print the key value. If missing, explain:
   - Generate a key at Root Dashboard → Workbench → API Keys → Create API Key
   - Create `.root-auth` with contents: `ROOT_API_KEY=sandbox_<key>`
   - Add `.root-auth` to `.gitignore` — never commit this file

4. **Check config**
   Read `.root-config.json` and confirm it is valid JSON. Show the module name and any key fields (e.g. `code_file_order`, `policyholder_type`) so the user can verify they're in the right module.

5. **Report**
   Summarise what passed and what (if anything) needs fixing before proceeding.
