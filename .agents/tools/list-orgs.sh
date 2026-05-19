#!/usr/bin/env bash
# list-orgs.sh
# Lists every org the current AWS creds can see in the organizations table.
# Useful for seeding ROOT_ORG_IDS for multi-org fan-out.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"
require_env

qid="$(run_athena "SELECT organization_id, name FROM organizations ORDER BY name")"
fetch_results "$qid"
