# Pattern Scoring Benchmark

Date: 2026-06-13
Phase: 3 deterministic scoring

## Purpose

`scripts/score-patterns.py` ranks repeated `skill-fog` patterns without network access, API keys, or non-stdlib Python dependencies. It is an offline benchmark tool only; it does not mutate `patterns.json`, fixtures, runtime hook code, or generated artifacts.

## Commands

Score a local pattern database read-only:

```bash
python3 scripts/score-patterns.py ~/.skill-fog/patterns.json
python3 scripts/score-patterns.py --patterns ~/.skill-fog/patterns.json
```

Validate a fixture oracle:

```bash
python3 scripts/score-patterns.py --fixture fixtures/patterns/ranking-basic.json
python3 scripts/score-patterns.py --fixture fixtures/patterns/privacy-risk.json
```

If a fixture path is missing, the command exits nonzero with `missing file: <path>`. If the fixture exists but the oracle mismatches, output JSON includes `"ok": false` and a `failures` list.

## Input Schema

`patterns.json` input follows the existing skill-fog state shape:

```json
{
  "patterns": {
    "pattern-id": {
      "canonical": "normalized repeated prompt",
      "count": 3,
      "sessions": ["session-a", "session-b"],
      "examples": ["raw example already stored by skill-fog"],
      "last_seen": "2026-06-13T00:00:00Z",
      "status": "active",
      "manual_decision": "review_required",
      "desired_type": "skill",
      "reviewed_at": "2026-06-13T00:00:00Z"
    }
  }
}
```

Fixture input can use either top-level `patterns` or `input.patterns`. Fixtures may set top-level `now` to make recency deterministic.

## Output Schema

Default output is JSON:

```json
{
  "patterns": [
    {
      "pid": "pattern-id",
      "canonical": "redacted canonical",
      "examples": ["redacted examples"],
      "eligible": true,
      "raw_score": 70,
      "total_score": 70,
      "suggested_type": "skill",
      "raw_suggested_type": "skill",
      "confidence": "medium",
      "recommendation": "auto_propose",
      "components": {
        "eligibility": { "eligible": true, "evidence": "passed" },
        "frequency": { "points": 10, "max": 25, "evidence": "count=3" },
        "session_spread": { "points": 8, "max": 20, "evidence": "sessions=2" },
        "recency": { "points": 15, "max": 15, "evidence": "last_seen_age_days=0" },
        "actionability": { "points": 17, "max": 20, "evidence": "verbs=fix;object_signal" },
        "artifact_fit": { "points": 20, "max": 20, "evidence": "artifact.skill:skill" },
        "noise_penalty": { "points": 0, "min": -30, "evidence": "none" },
        "privacy_penalty": {
          "points": 0,
          "min": -50,
          "evidence": "none",
          "redaction_rule_ids": [],
          "redaction_succeeded": false
        },
        "manual_override": {
          "manual_decision": null,
          "desired_type": null,
          "reviewed_at": null,
          "applied": false
        }
      },
      "reasons": ["eligible repeated pattern"]
    }
  ]
}
```

`raw_score` and `total_score` are the deterministic score before manual recommendation changes. Manual overrides may change `recommendation` and `suggested_type`, but they do not change `raw_score`.

## Eligibility

A pattern is eligible only when all are true:

- `count >= 3`
- `len(sessions) >= 2`
- `status == "active"`
- no hard noise suppression rule applies
- no hard privacy suppression rule applies

Eligibility evidence is emitted in `components.eligibility`.

## Score Components

| Component | Range | Evidence |
| --- | ---: | --- |
| `frequency` | 0 to 25 | `count=<value>` |
| `session_spread` | 0 to 20 | `sessions=<value>` |
| `recency` | 0 to 15 | `last_seen_age_days=<value>` or `last_seen=missing` |
| `actionability` | 0 to 20 | verb, Korean action, object, and specificity signals |
| `artifact_fit` | 0 to 20 | classifier rule ID for `skill`, `command`, `agent`, or unknown |
| `noise_penalty` | 0 to -30 | noise rule ID or `none` |
| `privacy_penalty` | 0 to -50 | redaction rule IDs or `none` |

Scores are clamped to `0..100`.

## Recommendation Rules

| Recommendation | Rule |
| --- | --- |
| `auto_propose` | eligible, `total_score >= 70`, no privacy penalty, and confidence is `high` or `medium` |
| `review_required` | eligible and `40 <= total_score < 70`, or a privacy penalty was applied with successful redaction |
| `suppress` | ineligible, `total_score < 40`, `noise_penalty <= -30`, or `privacy_penalty <= -50` |

Manual decisions with `reviewed_at` can override the final recommendation:

- `accept`, `accepted`, `auto`, `auto_propose`, `propose` -> `auto_propose`
- `review`, `review_required`, `needs_review` -> `review_required`
- `reject`, `rejected`, `suppress`, `suppressed`, `skip` -> `suppress`

`desired_type` can override `suggested_type` when it is one of `skill`, `command`, or `agent`. The original classifier result remains in `raw_suggested_type`.

## Rule IDs

Privacy and redaction:

| Rule ID | Meaning | Penalty |
| --- | --- | ---: |
| `privacy.secret.aws_access_key` | AWS access key-like value | -20 |
| `privacy.secret.db_url` | database URL with credentials or host data | -20 |
| `privacy.secret.assignment` | `api_key`, `token`, `secret`, or password assignment | -20 |
| `privacy.secret.bearer` | bearer token-like value | -20 |
| `privacy.secret.long_token` | long token-like opaque value | -20 |
| `privacy.email` | email address | -20 |
| `privacy.local_path` | local absolute path | -10 |
| `privacy.private_url` | localhost or RFC1918 private URL | -20 |

Noise:

| Rule ID | Meaning | Penalty |
| --- | --- | ---: |
| `noise.too_short` | fewer than 10 characters | -30 |
| `noise.only_ack` | acknowledgement-only text | -30 |
| `noise.polite_closure` | thanks/closure text without reusable workflow value | -30 |
| `noise.benign_repeat` | common repeated prompts such as rerunning tests or continuing context | -30 |
| `noise.stack_trace` | stack trace or dependency noise | -30 |
| `noise.generated_blob` | generated structured blob | -20 |
| `noise.question_only` | broad question-only prompt | -10 |

Artifact fit:

| Rule ID Prefix | Meaning |
| --- | --- |
| `artifact.skill` | workflow, skill, guide, rubric, checklist, or Korean skill signal |
| `artifact.command` | command, CLI, script, hook, slash command, or Korean command signal |
| `artifact.agent` | agent, reviewer, specialist, engineer, planner, architect, or Korean agent signal |
| `artifact.unknown` | no explicit artifact signal |

## Fixture Oracle Schema

Fixture files may contain:

```json
{
  "now": "2026-06-13T00:00:00Z",
  "input": { "patterns": {} },
  "expected": {
    "order": ["pid-a", "pid-b"],
    "recommendations": {
      "pid-a": "auto_propose",
      "pid-b": "review_required"
    },
    "redactions": { "pid-secret": ["privacy.secret.assignment"] },
    "forbidden_output_values": ["raw-secret-value"],
    "manual_overrides": {
      "pid-manual": {
        "recommendation": "suppress",
        "suggested_type": "command",
        "raw_score_unchanged": true
      }
    }
  }
}
```

For Phase 3 fixtures, `expected.order` and `expected.recommendations` are required, non-empty, and authoritative. Validation compares `expected.order` against the full deterministic output order, not a prefix or subset. `expected.recommendations` may be an object keyed by pid or a list of `{ "pid": "...", "recommendation": "..." }` objects, but it must cover every scored pid exactly once and every listed label must match the scorer output. Empty or missing strict order and recommendation oracles make a Phase 3 fixture fail validation even if legacy fields are present.

Aliases accepted by the validator:

- `expected_order` for `order`
- `recommendation_labels` for `recommendations`
- `redaction_expectations` for `redactions`
- `manual_override_effects` for `manual_overrides`

Legacy `expected_scoring` arrays remain supported only for non-Phase-3 compatibility paths and for deriving redaction or manual-override checks when no strict replacement exists. They are not authoritative for Phase 3 order or recommendation labels.

## Fixture Evidence

Current local fixture state:

- `fixtures/patterns/` exists.
- `fixtures/patterns/ranking-basic.json` contains strict full-order `expected.order` and full-label-coverage `expected.recommendations` and validates with `"ok": true`.
- `fixtures/patterns/privacy-risk.json` contains strict full-order `expected.order`, full-label-coverage `expected.recommendations`, redaction expectations, forbidden raw-value checks, and manual override expectations, and validates with `"ok": true`.

Validation evidence from this workspace:

```bash
python3 scripts/score-patterns.py --fixture fixtures/patterns/ranking-basic.json
# exits 0 with "ok": true

python3 scripts/score-patterns.py --fixture fixtures/patterns/privacy-risk.json
# exits 0 with "ok": true
```

Phase 3 completion requires both fixture commands to exit 0 and report `"ok": true`.
Corrupting a strict oracle, such as reversing `expected.order` or changing a recommendation label, must make `--fixture` exit nonzero with `"ok": false` and a populated `failures` list.
