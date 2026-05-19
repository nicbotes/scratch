# Reference: Output Formats and Delivery

Once you have an answer, where is it going? This decision matrix pairs **consumer** with **format** and **delivery channel** so the agent doesn't pick by reflex.

Sibling reference: `extension-shapes.md` decides **what artefact** a discovery becomes (recipe / skill / view / golden / …). This file decides **how that artefact's output is shaped and delivered.**

> **Pre-aggregate first.** This matrix is for *machine* consumers (data pipelines, Node/Python apps, ops queues, BI tools). When the **agent itself** is the consumer — i.e. the answer needs interpretation, not just delivery — the right path is `pre-aggregate` instead: pull once to a file or S3, then loop in `duckdb-query.sh` for free. Only the small summary enters context. See `skills/pre-aggregate.md` and rules.md #24.

## Decision matrix

| Consumer | Format | Tool | Delivery |
|---|---|---|---|
| Human, ad-hoc in chat | CSV | `athena-query.sh` (default) | stdout |
| Human, ad-hoc as a file | CSV | `athena-query.sh > file.csv` | local file |
| Ops queue, working through the list | CSV | `ops-dataset` view → `athena-query.sh` | local file / Sheets paste |
| Ops queue, recurring delivery | CSV | `ops-dataset` view | `/dev-data-export` (scheduled SFTP / S3 / HTTPS) |
| Data pipeline (Spark / dbt / Polars) | **Parquet** | **`athena-unload.sh ... --format parquet`** | S3 (`s3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/unloads/<name>/`); pipeline pulls |
| Node / Python app, batch pull (small) | JSON or JSONL | `athena-query.sh --format jsonl > file.jsonl` then `aws s3 cp` | S3; app pulls |
| Node / Python app, batch pull (large) | JSON | `athena-unload.sh ... --format json` | S3; app pulls |
| Node / Python app, push | JSON | *deferred* — use `curl` with explicit user confirmation per call | HTTPS POST |
| Exec / board pack | Styled HTML / PDF | *deferred* — Jinja2 + WeasyPrint as one-off, or `/dev-documents` if the policy-document pattern fits | local file / email link |
| Spreadsheet user (Excel) | xlsx | *deferred* — one-off `pandas` + `openpyxl` Python script | local file |
| BI tool (Power BI / Tableau / Looker / DBeaver) | SQL view | `bi-view` → `save-view.sh fact_*/dim_*` | JDBC/ODBC via `/dev-data-adapter` |
| Compliance / regulator | CSV + manifest | `export-results.sh` | `.agents/evidence/<ts>-<name>/` (gitignored, hash-sealed) |

## Format notes

**CSV**
- Universal, human-readable, lossy on types (everything becomes string when re-parsed).
- Default for anything a person will open directly.

**JSON** (single array)
- One HTTP response body, one `json.load()` call.
- Easy for small results, awkward for large (must fit in memory both sides).

**JSONL** (one object per line)
- The Node/Python streaming format. Each line is a complete JSON object.
- Preferred over a single JSON array for any result above a few thousand rows.

**Parquet** (via Athena `UNLOAD`)
- Columnar, typed, snappy-compressed by default. Cheap to re-read.
- Use for any result a data pipeline will consume more than once.
- `athena-unload.sh` writes directly to S3 — no CSV roundtrip, no type loss.
- See rules.md #21.

**ORC**
- Similar to Parquet; choose Parquet unless the downstream specifically wants ORC.

**TSV**
- For paste-into-spreadsheet workflows where a comma in a field breaks CSV.

## Delivery notes

**stdout** — `athena-query.sh "..."` — the chat fallback. Default.

**Local file** — `athena-query.sh "..." > file.<ext>` — quickest "give me a file" path.

**S3 (Athena unloads prefix)** — `athena-unload.sh` writes to `s3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/unloads/<name>/`. The downstream consumer reads from that prefix. Decoupled, no allowlist needed (same org, same bucket).

**`.agents/evidence/<ts>-<name>/`** — `export-results.sh`. CSV + manifest with sha256 + query id. The compliance contract.

**`/dev-data-export`** (recurring SFTP/S3/HTTPS) — the platform's scheduled-delivery feature. Configure once in product-module settings; the platform delivers on cadence. **Use this for anything recurring** — the ad-hoc tools below are for one-off and dev workflows.

**Ad-hoc SFTP push** — *deferred*. Until a tool lands, run `lftp` or `sftp` manually with explicit confirmation from the user (rule #22). For recurring delivery, use `/dev-data-export`.

**Ad-hoc HTTPS push** — *deferred*. Until a tool lands, use `curl` with **explicit user confirmation per call**. The decided safety model (rule #22) is per-call confirmation; an allowlist (`OUTPUT_ALLOWED_HOSTS`) will be layered on when the tool is built.

## Deferred — named so the next iteration knows what to build

Each row in the matrix marked *deferred* gets a tool when:
- ≥3 `observe` notes of kind `tool-gap` accumulate against the same missing tool, OR
- A specific delivery commitment to a stakeholder requires it.

The deferred list:
- `csv-to-xlsx.sh` — Excel output. Python + `openpyxl` toolchain envisaged.
- `render-report.sh` — styled HTML / PDF reports. Either Jinja2 + WeasyPrint or reuse `/dev-documents` (Handlebars + Root render).
- `deliver-sftp.sh` — ad-hoc SFTP push.
- `deliver-http.sh` — ad-hoc HTTPS POST with per-call user confirmation.

## Worked examples

### Parquet for a data pipeline

```bash
bash .agents/tools/athena-unload.sh policies_2025q1 \
  "SELECT policy_id, status, monthly_premium, from_iso8601_timestamp(created_at) AS created_ts
   FROM policies
   WHERE environment = 'production'
     AND created_at >= '2025-01-01' AND created_at < '2025-04-01'" \
  --format parquet --compression snappy
# → unload complete: s3://<bucket>/<org_id>/unloads/policies_2025q1/
```

Pipeline-side (Python + pyarrow):
```python
import pyarrow.dataset as ds
table = ds.dataset("s3://<bucket>/<org_id>/unloads/policies_2025q1/",
                   format="parquet").to_table()
```

### JSONL feed for a Node app

```bash
bash .agents/tools/athena-query.sh --format jsonl \
  "SELECT policy_id, status FROM policies WHERE environment='production' LIMIT 10000" \
  > policies.jsonl

aws s3 cp policies.jsonl "s3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/feeds/policies.jsonl"
```

Node-side:
```js
const readline = require('readline');
const fs = require('fs');
const rl = readline.createInterface({ input: fs.createReadStream('policies.jsonl') });
rl.on('line', (line) => {
  const row = JSON.parse(line);
  // ...
});
```

### Single-shot JSON for an API client

```bash
bash .agents/tools/athena-query.sh --format json \
  "SELECT status, COUNT(*) AS count FROM policies WHERE environment='production' GROUP BY status" \
  | jq .
```

→ Cross-references: `extension-shapes.md` (what artefact does this discovery become?), `/dev-data-export` (recurring delivery), `bi-view` (BI tool consumer path), `compliance-query` (compliance evidence path).
