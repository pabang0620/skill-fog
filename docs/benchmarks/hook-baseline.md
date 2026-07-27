# Hook Baseline

**Phase:** 1B baseline documentation
**Date:** 2026-06-13

This document records the Phase 1B baseline for the current hook implementation. The default 30-run benchmark was stopped after over 150 seconds while processing medium run 26, so this phase records a one-run baseline and uses provisional thresholds.

## Fixture Baseline

The fixture JSONL files under `fixtures/transcripts` exist with these measured sizes:

| Fixture | Lines | Bytes |
| --- | ---: | ---: |
| `claude-jsonl-v1` | 9 | 725 |
| `claude-jsonl-v2` | 7 | 1074 |
| `cursor-regression` | 8 | 951 |
| `small` | 20 | 2031 |
| `medium` | 180 | 20600 |
| `large-incremental` | 900 | 126676 |

## Commands Run

```bash
bash -n scripts/bench-hook.sh
scripts/bench-hook.sh --assert-only
scripts/bench-hook.sh --benchmark-only --runs 1 --warmups 0
```

Manual smoke coverage also concatenated `claude-jsonl-v1` and `claude-jsonl-v2`; that run created `patterns=4` and `pending=1`.

## Verification Results

- `bash -n scripts/bench-hook.sh` passed.
- `scripts/bench-hook.sh --assert-only` passed.
- Manual smoke with concatenated v1+v2 produced `patterns=4` and `pending=1`.

## One-Run Benchmark Baseline

Benchmark command:

```bash
scripts/bench-hook.sh --benchmark-only --runs 1 --warmups 0
```

Environment:

| Field | Value |
| --- | --- |
| Date | `2026-06-13T12:41:57Z` |
| Machine | `Linux x86_64` |
| Cores | 12 |

Results:

| Fixture | p50 | p95 | max |
| --- | ---: | ---: | ---: |
| `small` | 1126.334 ms | 1126.334 ms | 1126.334 ms |
| `medium` | 6085.669 ms | 6085.669 ms | 6085.669 ms |
| `large-incremental` | 5825.195 ms | 5825.195 ms | 5825.195 ms |

Because this baseline uses `--runs 1`, p50, p95, and max are identical for each fixture.

## Provisional Thresholds

Initial thresholds for the current hook are grounded in the measured one-run baseline:

- Warn if p95 exceeds `7000 ms`.
- Fail if p95 exceeds `10000 ms`.

These thresholds are intentionally provisional. Phase 4 should tighten them after hook optimization and a stable multi-run benchmark are available.
