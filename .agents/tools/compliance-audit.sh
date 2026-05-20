#!/usr/bin/env bash
# compliance-audit.sh [--session <id>] [--since <YYYY-MM-DD>] [--output <path>]
#
# Produces a markdown report summarising every sensitive-touching tool
# invocation in the session log:
#   - which tool, when, against which org (hash)
#   - did the operator use --pii-required, with what reason
#   - which PII / restricted / json_sensitive columns were touched
#   - row count of the result (no values — never values)
#
# The deliverable a compliance officer reads after-the-fact to verify the
# framework's PII boundary was respected.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

session_id=""
since=""
output=""

while (( $# )); do
  case "$1" in
    --session) session_id="$2"; shift 2 ;;
    --since)   since="$2";      shift 2 ;;
    --output)  output="$2";     shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

sessions_dir="$AGENTS_ROOT/sessions"
if [[ ! -d "$sessions_dir" ]]; then
  echo "no sessions directory found at $sessions_dir" >&2
  exit 0
fi

# Determine the files to read
files=()
if [[ -n "$session_id" ]]; then
  f="$sessions_dir/$session_id.jsonl"
  [[ -f "$f" ]] || { echo "error: no session log at $f" >&2; exit 64; }
  files=("$f")
else
  shopt -s nullglob
  for f in "$sessions_dir"/*.jsonl; do
    base="$(basename "$f" .jsonl)"
    if [[ -n "$since" ]]; then
      [[ "$base" < "$since" ]] && continue
    fi
    files+=("$f")
  done
fi

if (( ${#files[@]} == 0 )); then
  echo "no session logs match the filter"
  exit 0
fi

# Build report via python (jsonl parsing is brittle in bash)
report="$(python3 - "${files[@]}" <<'EOF'
import json, sys
from collections import Counter

files = sys.argv[1:]
sensitive_lines = []
total = 0
pii_required_count = 0
row_cap_hits = 0
sessions = set()

for path in files:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            total += 1
            sessions.add(rec.get("session", "?"))
            tool = rec.get("tool", "?")
            # Sensitive markers: pii_required=true, or tool=pii-lookup, or reason field present
            sensitive = (
                rec.get("pii_required") is True
                or tool == "pii-lookup"
                or rec.get("pii_to_file") is True
                or "reason" in rec
            )
            if rec.get("row_cap_hit") is True:
                row_cap_hits += 1
            if sensitive:
                if rec.get("pii_required") is True:
                    pii_required_count += 1
                sensitive_lines.append(rec)

print(f"# Compliance audit\n")
print(f"- Session(s): {', '.join(sorted(sessions))}")
print(f"- Total tool invocations: {total}")
print(f"- Sensitive-touching invocations: {len(sensitive_lines)}")
print(f"- `--pii-required` overrides used: {pii_required_count}")
print(f"- Row-cap hits (context safety): {row_cap_hits}\n")

if not sensitive_lines:
    print("## No sensitive-touching invocations\n")
    print("Every recorded tool call was either non-sensitive or routed PII output to disk/S3 without entering the agent's context. No further review required.\n")
else:
    print("## Sensitive-touching invocations\n")
    print("| Time (UTC) | Tool | Override | Reason | Touched columns | Details |")
    print("|---|---|---|---|---|---|")
    for r in sensitive_lines:
        ts = r.get("ts", "?")
        tool = r.get("tool", "?")
        override = "yes" if r.get("pii_required") is True else ("to-file" if r.get("pii_to_file") is True else "-")
        reason = (r.get("reason") or "").replace("|", "\\|").replace("\n", " ")
        # Compose the touched-columns column from the per-bucket fields,
        # omitting empty buckets so the cell stays readable.
        touched_parts = []
        for label, key in (
            ("pii", "touched_pii"),
            ("restricted", "touched_restricted"),
            ("json_sensitive", "touched_json_sensitive"),
            ("json_paths", "touched_json_paths"),
            # pii-lookup uses a different shape: the requested columns are in touched_columns
            ("columns", "touched_columns"),
        ):
            v = r.get(key)
            if v:
                touched_parts.append(f"{label}={v}")
        touched = "; ".join(touched_parts) or "-"
        # Tool-specific details (table, id_col, rows)
        detail_parts = []
        for k in ("table", "id_col", "rows"):
            if k in r:
                detail_parts.append(f"{k}={r[k]}")
        detail = ", ".join(detail_parts) or "-"
        print(f"| {ts} | {tool} | {override} | {reason} | {touched} | {detail} |")
    print()
    # Aggregate view: which columns were touched across this audit window?
    col_counter = Counter()
    for r in sensitive_lines:
        for key in ("touched_pii", "touched_restricted", "touched_json_sensitive", "touched_columns"):
            v = r.get(key) or ""
            for c in v.split(","):
                c = c.strip()
                if c and c != "*":
                    col_counter[c] += 1
    if col_counter:
        print("## Most-touched sensitive columns\n")
        print("| Column | Times touched |")
        print("|---|---|")
        for col, n in col_counter.most_common(20):
            print(f"| `{col}` | {n} |")
        print()
EOF
)"

if [[ -n "$output" ]]; then
  echo "$report" > "$output"
  echo "wrote audit report: $output" >&2
else
  echo "$report"
fi
