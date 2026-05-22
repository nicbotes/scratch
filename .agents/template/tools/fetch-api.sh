#!/usr/bin/env bash
# fetch-api.sh <endpoint-or-full-url>
#   [--auth bearer|header|none]
#   [--auth-header-name X-API-Key]
#   [--query "k=v&k=v"]
#   [--method GET|POST|PUT|PATCH|DELETE]
#   [--body @file|"<json>"]
#   [--paginate link|cursor|offset|none]
#   [--cursor-key next_cursor]               # for --paginate cursor
#   [--cursor-param cursor]                  # query-param name to send the cursor as
#   [--page-size 100] [--max-pages N]
#   [--rate-limit-header X-RateLimit-Remaining]
#   [--rate-limit-reset-header X-RateLimit-Reset]
#   [--source <name>] [--entity <name>]
#   [--out <path>]
#   [--jq-extract '.[]']
#   [--dry-run]
#
# Generic authenticated HTTP client. Reads $API_BASE_URL + $API_TOKEN from env.
# Writes JSONL to data/raw/<source>/<entity>/<utc-ts>.jsonl and a sibling
# .manifest.json. See references/api-discovery.md and rules.md.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

auth="bearer"
auth_header_name=""
query=""
method="GET"
body=""
paginate="none"
cursor_key=""
cursor_param="cursor"
page_size=""
max_pages=0
rl_remaining_header="X-RateLimit-Remaining"
rl_reset_header="X-RateLimit-Reset"
source_name=""
entity=""
out=""
jq_extract='.'
dry_run=0
positional=()

while (( $# )); do
  case "$1" in
    --auth)                  auth="$2";                shift 2 ;;
    --auth-header-name)      auth_header_name="$2";    shift 2 ;;
    --query)                 query="$2";               shift 2 ;;
    --method)                method="$2";              shift 2 ;;
    --body)                  body="$2";                shift 2 ;;
    --paginate)              paginate="$2";            shift 2 ;;
    --cursor-key)            cursor_key="$2";          shift 2 ;;
    --cursor-param)          cursor_param="$2";        shift 2 ;;
    --page-size)             page_size="$2";           shift 2 ;;
    --max-pages)             max_pages="$2";           shift 2 ;;
    --rate-limit-header)       rl_remaining_header="$2"; shift 2 ;;
    --rate-limit-reset-header) rl_reset_header="$2";     shift 2 ;;
    --source)                source_name="$2";         shift 2 ;;
    --entity)                entity="$2";              shift 2 ;;
    --out)                   out="$2";                 shift 2 ;;
    --jq-extract)            jq_extract="$2";          shift 2 ;;
    --dry-run)               dry_run=1;                shift ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)  positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

endpoint="${1:-}"
[[ -z "$endpoint" ]] && { echo 'usage: fetch-api.sh <endpoint> [flags]' >&2; exit 64; }

# Dependencies
for bin in curl jq python3; do
  command -v "$bin" >/dev/null || { echo "error: $bin not on PATH" >&2; exit 64; }
done

# Resolve full URL
if [[ "$endpoint" =~ ^https?:// ]]; then
  url="$endpoint"
else
  require_api_env
  url="${API_BASE_URL%/}/${endpoint#/}"
fi

# Auth → curl headers
auth_headers=()
case "$auth" in
  bearer)
    require_api_token
    auth_headers=(-H "Authorization: Bearer ${API_TOKEN}")
    ;;
  header)
    require_api_token
    [[ -z "$auth_header_name" ]] && { echo "error: --auth header requires --auth-header-name" >&2; exit 64; }
    auth_headers=(-H "${auth_header_name}: ${API_TOKEN}")
    ;;
  none) : ;;
  *) echo "error: --auth must be bearer|header|none (got: $auth)" >&2; exit 64 ;;
esac

# Build initial query
initial_query="$query"
if [[ -n "$page_size" ]]; then
  case "$paginate" in
    link|cursor|offset)
      if [[ -n "$initial_query" ]]; then
        initial_query+="&per_page=$page_size"
      else
        initial_query="per_page=$page_size"
      fi
      ;;
  esac
fi

# Default --out path: data/raw/<source>/<entity>/<utc-ts>.jsonl
ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
if [[ -z "$out" ]]; then
  if [[ -z "$source_name" || -z "$entity" ]]; then
    echo "error: --out OR both --source and --entity required" >&2
    exit 64
  fi
  out_dir="$AGENTS_ROOT/data/raw/$source_name/$entity"
  mkdir -p "$out_dir"
  out="$out_dir/${ts}.jsonl"
fi

manifest_path="${out%.jsonl}.manifest.json"
hash="$(api_base_hash)"

if (( dry_run )); then
  cat <<EOF
[dry-run]
  url:           $url
  auth:          $auth $auth_header_name
  method:        $method
  body:          $body
  query:         $initial_query
  paginate:      $paginate (cursor_key=$cursor_key cursor_param=$cursor_param page_size=$page_size max_pages=${max_pages:-unlimited})
  out:           $out
  manifest:      $manifest_path
  jq-extract:    $jq_extract
EOF
  exit 0
fi

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
> "$out"

pages=0
records=0
bytes=0
complete=true
next_url=""
next_cursor=""
offset=0
current_query="$initial_query"

while :; do
  # Compose request URL
  req_url="$url"
  if [[ "$paginate" == "link" && -n "$next_url" ]]; then
    # Link-header pagination: server gives us the full next URL
    req_url="$next_url"
    current_query=""
  fi
  if [[ -n "$current_query" ]]; then
    if [[ "$req_url" == *\?* ]]; then req_url="${req_url}&${current_query}"; else req_url="${req_url}?${current_query}"; fi
  fi

  _debug "fetch page=$((pages+1)) url=$req_url"

  curl_args=(-sS --fail-with-body -m 60 -X "$method")
  if (( ${#auth_headers[@]} )); then
    curl_args+=("${auth_headers[@]}")
  fi
  curl_args+=(-H "Accept: application/json")
  if [[ -n "$body" ]]; then
    curl_args+=(-H "Content-Type: application/json")
    if [[ "$body" == @* ]]; then
      curl_args+=(--data-binary "$body")
    else
      curl_args+=(--data-binary "$body")
    fi
  fi
  curl_args+=(-D /tmp/fetch-api.headers.$$ -o /tmp/fetch-api.body.$$ "$req_url")

  set +e
  curl "${curl_args[@]}"
  status=$?
  set -e

  if (( status != 0 )); then
    # On 429, honour rate-limit reset
    http_code="$(awk 'NR==1{print $2; exit}' /tmp/fetch-api.headers.$$ 2>/dev/null || echo "")"
    if [[ "$http_code" == "429" ]]; then
      reset="$(grep -i "^$rl_reset_header:" /tmp/fetch-api.headers.$$ 2>/dev/null | awk '{print $2}' | tr -d '\r')"
      now="$(date +%s)"
      sleep_for=60
      if [[ "$reset" =~ ^[0-9]+$ ]]; then
        sleep_for=$(( reset - now ))
        (( sleep_for < 1 )) && sleep_for=1
        (( sleep_for > 3600 )) && sleep_for=3600
      fi
      echo "[fetch-api] 429 rate-limited; sleeping ${sleep_for}s until reset" >&2
      sleep "$sleep_for"
      continue
    fi
    # 5xx → exponential backoff retry handled by curl --retry? Keep simple: bail out
    echo "[fetch-api] HTTP $http_code on page $((pages+1)); leaving manifest as partial" >&2
    complete=false
    break
  fi

  # Successful page
  page_bytes="$(wc -c < /tmp/fetch-api.body.$$ | tr -d ' ')"
  bytes=$(( bytes + page_bytes ))
  pages=$(( pages + 1 ))

  # Extract records and append to JSONL
  page_records=0
  if jq -e "$jq_extract" /tmp/fetch-api.body.$$ >/dev/null 2>&1; then
    # If the extract yields an array of objects (typical: .items[] or .[]),
    # write each as one line. If it yields a single object, write that one.
    page_records=$(jq -c "$jq_extract" /tmp/fetch-api.body.$$ | tee -a "$out" | wc -l | tr -d ' ')
  else
    echo "[fetch-api] jq extract '$jq_extract' produced nothing on page $pages" >&2
  fi
  records=$(( records + page_records ))

  # Pre-emptive rate-limit pause if remaining = 0
  remaining="$(grep -i "^$rl_remaining_header:" /tmp/fetch-api.headers.$$ 2>/dev/null | awk '{print $2}' | tr -d '\r')"
  if [[ "$remaining" == "0" ]]; then
    reset="$(grep -i "^$rl_reset_header:" /tmp/fetch-api.headers.$$ 2>/dev/null | awk '{print $2}' | tr -d '\r')"
    now="$(date +%s)"
    sleep_for=60
    if [[ "$reset" =~ ^[0-9]+$ ]]; then
      sleep_for=$(( reset - now ))
      (( sleep_for < 1 )) && sleep_for=1
      (( sleep_for > 3600 )) && sleep_for=3600
    fi
    echo "[fetch-api] rate-limit exhausted; sleeping ${sleep_for}s" >&2
    sleep "$sleep_for"
  fi

  # Determine next page
  next_url=""
  next_cursor=""
  case "$paginate" in
    none)
      break
      ;;
    link)
      link_header="$(grep -i '^link:' /tmp/fetch-api.headers.$$ 2>/dev/null | head -n1 | tr -d '\r')"
      next_url="$(printf '%s' "$link_header" | python3 -c '
import re, sys
line = sys.stdin.read()
m = re.search(r"<([^>]+)>;\s*rel=\"next\"", line)
print(m.group(1) if m else "")
')"
      [[ -z "$next_url" ]] && break
      ;;
    cursor)
      [[ -z "$cursor_key" ]] && { echo "error: --paginate cursor requires --cursor-key" >&2; exit 64; }
      next_cursor="$(jq -r ".${cursor_key} // empty" /tmp/fetch-api.body.$$)"
      [[ -z "$next_cursor" || "$next_cursor" == "null" ]] && break
      current_query="${query:+${query}&}${cursor_param}=${next_cursor}"
      [[ -n "$page_size" ]] && current_query+="&per_page=${page_size}"
      ;;
    offset)
      if (( page_records == 0 )); then break; fi
      offset=$(( offset + (page_size > 0 ? page_size : page_records) ))
      current_query="${query:+${query}&}offset=${offset}"
      [[ -n "$page_size" ]] && current_query+="&per_page=${page_size}"
      ;;
    *) echo "error: --paginate must be link|cursor|offset|none (got: $paginate)" >&2; exit 64 ;;
  esac

  if (( max_pages > 0 )) && (( pages >= max_pages )); then
    # If the server has more pages but we hit the cap, mark partial.
    case "$paginate" in
      link)   [[ -n "$next_url" ]]    && complete=false ;;
      cursor) [[ -n "$next_cursor" ]] && complete=false ;;
      offset) (( page_records > 0 )) && complete=false ;;
    esac
    [[ "$complete" != "true" ]] && echo "[fetch-api] hit --max-pages=$max_pages; manifest marked complete=false" >&2
    break
  fi
done

rm -f /tmp/fetch-api.headers.$$ /tmp/fetch-api.body.$$

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Manifest (built as JSON via python with True/False booleans)
complete_py="True"
[[ "$complete" != "true" ]] && complete_py="False"
python3 - "$source_name" "$entity" "$endpoint" "$url" "$method" "$paginate" \
  "$pages" "$records" "$bytes" "$complete_py" "$max_pages" \
  "$started_at" "$finished_at" "$out" "$hash" > "$manifest_path" <<'PY'
import json, sys
source, entity, endpoint, url, method, paginate, pages, records, bytes_, complete, max_pages, started_at, finished_at, out, hash_ = sys.argv[1:]
m = {
    "source": source,
    "entity": entity,
    "endpoint": endpoint,
    "url": url,
    "method": method,
    "paginate": paginate,
    "pages": int(pages),
    "records": int(records),
    "bytes": int(bytes_),
    "complete": complete == "True",
    "max_pages_requested": int(max_pages),
    "started_at": started_at,
    "finished_at": finished_at,
    "out": out,
    "api_base_hash": hash_,
}
print(json.dumps(m, indent=2))
PY

_session_log "fetch-api" "$([[ "$complete" == "true" ]] && echo true || echo false)" "0" "$bytes"
_mixpanel_track "Data Landed" "tool=fetch-api" \
  "source=$source_name" "entity=$entity" \
  "pages=$pages" "records=$records" "bytes=$bytes" \
  "complete=$complete"

echo "path=$out pages=$pages records=$records bytes=$bytes complete=$complete"
