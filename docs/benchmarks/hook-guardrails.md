# Hook Performance Guardrails

**Phase:** 4 hook performance guardrails
**Date:** 2026-06-13

This document describes the `scripts/bench-hook.sh` performance budget checks and JSON reporting added for Phase 4.

## Commands

Default output remains a markdown benchmark table:

```bash
scripts/bench-hook.sh --benchmark-only --runs 1 --warmups 0
```

Machine-readable output is enabled with `--json`:

```bash
scripts/bench-hook.sh --benchmark-only --runs 1 --warmups 0 --json
```

The p95 budget thresholds default to the provisional baseline in `docs/benchmarks/hook-baseline.md`:

- Warn: `7000 ms`
- Fail: `10000 ms`

Thresholds can be overridden per run:

```bash
scripts/bench-hook.sh --benchmark-only --runs 1 --warmups 0 --warn-p95-ms 6000 --fail-p95-ms 9000
```

For privacy-safe execution metadata, `--debug` prints only harness settings and threshold metadata to stderr. It does not print transcript lines, examples, or hook payload contents.

## Incremental Benchmark Semantics

`large-incremental` is a cursor benchmark, but each warmup and measured iteration starts from the same prepared cursor state. The harness creates a template temp HOME with the cursor positioned before the final 100 fixture lines, copies that HOME for every iteration, and verifies that the run advances the cursor from the template offset.

This avoids measuring a draining cursor where warmups or earlier measured runs move the shared cursor to EOF and later measured runs become no-op samples.

## JSON Schema

The JSON output is an object with these top-level fields:

| Field | Type | Description |
| --- | --- | --- |
| `schema_version` | number | Schema version for consumers. Current value: `1`. |
| `generated_at` | string | UTC timestamp for the benchmark run. |
| `git_sha` | string | Short git SHA, or `unknown` when unavailable. |
| `machine` | string | OS/kernel/architecture and core count summary. |
| `runs` | number | Timed benchmark runs per fixture. |
| `warmups` | number | Untimed warmup runs per fixture. |
| `thresholds` | object | Active p95 thresholds. |
| `fixtures` | array | Per-fixture benchmark result objects. |
| `violations` | array | Fail-budget violations, if any. |

`thresholds` contains:

| Field | Type | Description |
| --- | --- | --- |
| `warn_p95_ms` | number | p95 warning threshold in milliseconds. |
| `fail_p95_ms` | number | p95 failure threshold in milliseconds. |

Each `fixtures[]` object contains:

| Field | Type | Description |
| --- | --- | --- |
| `name` | string | Fixture stem, such as `small`. |
| `path` | string | Repo-relative fixture path. |
| `bytes` | number | Fixture byte size. |
| `lines` | number | Fixture line count. |
| `p50_ms` | number | p50 hook runtime in milliseconds. |
| `p95_ms` | number | p95 hook runtime in milliseconds. |
| `max_ms` | number | Maximum hook runtime in milliseconds. |
| `status` | string | `ok`, `warn`, or `performance_budget_exceeded`. |

Each `violations[]` object contains:

| Field | Type | Description |
| --- | --- | --- |
| `reason` | string | Always `performance_budget_exceeded` for fail-budget violations. |
| `fixture` | string | Fixture name. |
| `p95_ms` | number | Measured p95 runtime. |
| `threshold_ms` | number | Active fail threshold. |

## Budget Behavior

The benchmark exits successfully when all fixture p95 values are at or below the fail threshold.

When a fixture p95 exceeds the warn threshold but not the fail threshold, the fixture status is `warn` and the process exits successfully.

When a fixture p95 exceeds the fail threshold:

- The fixture status is `performance_budget_exceeded`.
- JSON output includes a matching `violations[]` entry.
- Markdown output prints a privacy-safe `performance_budget_exceeded fixture=... p95_ms=... threshold_ms=...` line to stderr.
- The process exits nonzero.

The benchmark output intentionally contains only fixture paths, sizes, counts, timings, status values, threshold metadata, git SHA, and machine summary. It does not include raw transcript lines, prompt examples, hook stdin payloads, or derived message text.

## Validation Evidence

Commands run from `<repo-root>`:

```bash
bash -n scripts/bench-hook.sh
scripts/bench-hook.sh --assert-only
scripts/bench-hook.sh --benchmark-only --runs 3 --warmups 1 --json
scripts/bench-hook.sh --benchmark-only --runs 1 --warmups 0 --fail-p95-ms 1 --json
scripts/bench-hook.sh --benchmark-only --runs 1 --warmups 0 --fail-p95-ms 1
```

Results:

- `bash -n scripts/bench-hook.sh` passed.
- `scripts/bench-hook.sh --assert-only` passed.
- `--benchmark-only --runs 3 --warmups 1 --json` produced 3 fixture objects with statuses `ok`, `ok`, `ok`; `large-incremental` reported p50 `4258.979 ms`, p95 `4284.980 ms`, and max `4287.869 ms`.
- During the multi-run JSON benchmark, each `large-incremental` warmup and measured run copied the same cursor template and passed the built-in cursor advancement assertion, so measured samples were not EOF/no-op runs caused by cursor carryover.
- The low-threshold JSON run exited with code `2` and reported `performance_budget_exceeded` for `small`, `medium`, and `large-incremental`.
- The low-threshold markdown run exited with code `2`; stderr matched `performance_budget_exceeded fixture=(small|medium|large-incremental) p95_ms=[0-9.]+ threshold_ms=1.000`, and the markdown table included `performance_budget_exceeded` statuses.
- A privacy scan over the JSON output for token/API-key patterns, email addresses, and database URLs found no matches.
