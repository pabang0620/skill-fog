# Artifact Eval Benchmark

Date: 2026-06-14
Phase: 5 deterministic artifact evaluation

## Purpose

`scripts/run-evals.sh` and `scripts/eval-artifacts.py` validate generated skill, command, and agent drafts with local stdlib-only checks. The evaluator is offline: it uses no network, no API calls, and no writes to `~/.claude`, `~/.codex/skills`, or the real `HOME`.

## Commands

Run one fixture:

```bash
bash scripts/run-evals.sh --case good-skill
```

Run every artifact fixture:

```bash
bash scripts/run-evals.sh --all
```

The runner expects fixtures in `fixtures/artifacts/*.json`. If a selected fixture is missing, it exits nonzero with `run-evals: missing fixture for case '<case>': <path>`. If `--all` has no fixtures, it exits nonzero with `run-evals: no artifact fixtures found in <path>`.

## Fixture Schema

Fixtures are JSON objects. The evaluator accepts the artifact draft at top-level or under `artifact_draft`, `artifact`, `draft`, `input`, or `generated`.

```json
{
  "case_id": "good-skill",
  "expected_result": "pass",
  "expected_artifact_type": "skill",
  "artifact_draft": {
    "artifact_type": "skill",
    "name": "review-checklist",
    "description": "Use when reviewing a focused change with concrete evidence.",
    "trigger": "Use when a user asks for a code review of a local change.",
    "content": "# Review Checklist\n\n...",
    "completion_evidence": "Fixture includes verification evidence.",
    "confidence": "high"
  }
}
```

Supported expected results are `pass`, `fail`, and `review_required`. A low-confidence fixture should set `"confidence": "low"` and `"expected_result": "review_required"`; the output will include a simulated `draft_path` and `"installed_path": null`.

Missing or invalid `expected_result`, `expected.result`, or `expected.expected_result` is a fixture schema failure. Fixture schema failures return `"result": "fail"`, `"final_state": "fixture_schema_failed"`, and `"critical_failures": ["fixture_schema_error"]`; they do not write a simulated draft.

Every declared `required_sections` entry must be present as a markdown heading in the artifact body. Section names may use underscores, spaces, or hyphens interchangeably, so `completion_evidence`, `Completion Evidence`, and `Completion-Evidence` match the same required section.

## Output Schema

Single-case output is JSON:

```json
{
  "case_id": "good-skill",
  "expected_result": "pass",
  "result": "pass",
  "score": 100,
  "critical_failures": [],
  "warnings": [],
  "final_state": "draft_validated",
  "draft_path": "/tmp/skill-fog-artifact-evals.xxxxxx/drafts/good-skill.skill.md",
  "installed_path": null
}
```

`--all` wraps those objects:

```json
{
  "ok": true,
  "cases": []
}
```

## Thresholds

Critical failures auto-fail regardless of score:

| Failure | Meaning |
| --- | --- |
| `overbroad_trigger` | Trigger text applies to all or nearly all requests. |
| `privacy_leak` | Draft text contains secret-like, email, token, or credential material. |
| `wrong_artifact_type` | Actual artifact type does not match `expected_artifact_type`. |
| `missing_required_section` | A declared `required_sections` entry is absent from artifact markdown headings. |
| `missing_completion_evidence` | Fixture/draft lacks completion or verification evidence. |
| `production_destructive_action` | Draft instructs destructive production-like actions such as deleting real HOME, Claude, Codex, or skill-fog state. |

Noncritical warnings reduce the score. A noncritical case passes only when `score >= 80`. Low confidence returns `review_required` instead of installing or accepting the artifact.

## Evidence and Safety

The bash runner creates a temp `HOME` and passes a temp draft root to the Python evaluator. The Python evaluator may write a simulated draft under a resolved system temp directory only; unsafe `--draft-root` values are rejected before writing, including symlinks into real install paths such as `~/.claude` or `~/.codex/skills`. If `--draft-root` is omitted, the evaluator creates its own safe temp draft root. It never installs artifacts and always reports `"installed_path": null`. Reported temp draft paths are simulation evidence for that run, not installed artifacts.

The destructive fixtures cover shell commands against home install subpaths such as `rm -rf $HOME/.claude/skills/...` and natural-language deletion instructions for protected Codex and skill-fog roots such as `Delete ~/.codex/skills/...` and `Remove ~/.skill-fog/pending/...`.

Use the exact commands above as Phase 5 evidence. With no local artifact fixtures present, the expected evidence is a clear missing-fixture error rather than silent success.
