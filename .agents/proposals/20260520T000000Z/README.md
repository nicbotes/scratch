# Retro proposals — 2026-05-20

Output of the retro pass over `.agents/feedback/2026-05-19.jsonl` (16 observe notes) and the two platform feature requests filed in `proposals/2026-05-20-data-adapter-feature-requests.md`. Each file in this folder targets one piece of friction. Review per file; apply in the order below.

Per rules.md #13, this folder does **not** edit live files. Apply happens in a follow-up PR; each commit there references and deletes the proposal it implements.

## Apply order

| # | Proposal | Targets | Source notes | Dependencies |
|---|---|---|---|---|
| 1 | [01-prerequisites-duckdb-env-gitignore.md](./01-prerequisites-duckdb-env-gitignore.md) | `AGENTS.md`, `references/env-vars.md` | 07:29:00Z, 07:29:10Z, 07:36:13Z (×2) | — |
| 2 | [02-aws-region-auto-detect.md](./02-aws-region-auto-detect.md) | `tools/_lib.sh`, `references/env-vars.md`, `AGENTS.md`, `.env.example` | 09:05:16Z, 09:05:34Z | — |
| 3 | [03-to-file-row-count-fallback.md](./03-to-file-row-count-fallback.md) | `tools/athena-query.sh` | 14:19:59Z (rows=0 bug) + feature-request #2 | — |
| 4 | [04-glue-describe-tool.md](./04-glue-describe-tool.md) | new `tools/glue-describe.sh` | 13:44:00Z | — |
| 5 | [05-profile-table-env-column-guard.md](./05-profile-table-env-column-guard.md) | `tools/profile-table.sh` | 13:44:00Z (tail), 09:11:38Z | independent of #4 (uses Athena `DESCRIBE`) |
| 6 | [06-rules-timestamp-and-duckdb-types.md](./06-rules-timestamp-and-duckdb-types.md) | `rules.md`, `references/examples.md` | 14:03:13Z, 14:14:53Z, 14:19:59Z | — |
| 7 | [07-schema-missing-columns-callout.md](./07-schema-missing-columns-callout.md) | `references/schema.md` | 09:11:38Z | — |
| 8 | [08-rules-proactive-evidence-export.md](./08-rules-proactive-evidence-export.md) | `rules.md` (#11 broadened) | 13:15:38Z | — |

## Suggested commits in the apply PR

1. **Items 1 + 2** — Prerequisites + region auto-detect (smallest surface, biggest first-session impact).
2. **Items 3 + 5** — Bug-fix shaped: `--to-file` row count and `profile-table.sh` env guard.
3. **Items 4 + 6 + 7 + 8** — `glue-describe.sh` new capability + the doc/rule updates that go with it.

## Out of scope

- Stale local branches (`agents-example-use`, `claude/agent-cli-skills-JNcox`, `sample-build`, `worktree-dim-policyholder-view`) — handle separately.
- Platform feature requests (`s3:PutObject` grant, upstream row-count fix) — already filed in `proposals/2026-05-20-data-adapter-feature-requests.md`; awaiting Root team action.
- Surface-area extensions in `FUTURE.md` (view hygiene, cost baselines, lineage, sub-agents, dbt) — none has a clustering-of-three signal yet.
