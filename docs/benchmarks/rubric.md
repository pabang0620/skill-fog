# skill-fog Benchmark Rubric

Date: 2026-06-13
Status: Phase 0 benchmark artifact
Source plan: `docs/plans/skill-fog-benchmark-improvement-plan.md`

## Purpose

This rubric converts the benchmark evidence map into a repeatable review standard. Reviewers score six areas from 0 to 2, record evidence, and produce a baseline total before later implementation phases start.

Scoring scale:

| Score | Meaning | Required evidence |
| ---: | --- | --- |
| 0 | Fail | The repo cannot satisfy the area, evidence is missing, or the only evidence is unverifiable. |
| 1 | Partial | Some requirement is present, but a gap, warning, or missing fixture prevents a full pass. |
| 2 | Pass | The area has local evidence, fixtures or commands where applicable, and no known blocking gap. |

Total score range: 0 to 12.

## Scored Areas

| Area | 0 = fail | 1 = partial | 2 = pass | Evidence to record |
| --- | --- | --- | --- | --- |
| Install health | Install, doctor, or uninstall cannot be validated without touching real user state, or doctor output gives unusable remediation. | Temp-HOME install or doctor evidence exists, but idempotency, uninstall, or remediation checks are incomplete. | Temp-HOME install, doctor, reinstall, and uninstall checks pass without writing outside temp HOME, and doctor remediation commands are runnable. | Commands run, HOME used, doctor status summary, idempotency result, remaining warnings. |
| Prompt surface | `SKILL.md` is the only behavior surface and embeds detailed procedures without a routing map. | Some supporting-file intent exists, but top-level instructions still carry long implementation detail or no behavior matrix. | Top-level skill instructions route to supporting references/scripts through a documented progressive-disclosure map. | `SKILL.md` size, referenced files, behavior matrix, unchanged behavior assertions. |
| Recommendation ranking | Repeated patterns are surfaced without deterministic ranking, privacy risk handling, or oracle comparison. | Ranking exists but lacks fixture oracle coverage, severity/category metadata, or risk penalties. | Ranking output matches fixture oracles and applies category, severity, risk penalties, and redactions. | Fixture names, ranking output, oracle comparison, privacy-risk assertions. |
| Hook performance | Hook behavior has no fixture simulation or timing baseline. | Hook fixtures run or timing is recorded, but p50/p95, cursor behavior, or fixture size coverage is incomplete. | Hook fixtures prove pattern creation, pending creation, cursor non-reprocessing, and p50/p95 timing for small, medium, and large fixtures. | Fixture commands, run count, warmups, p50, p95, max, machine/date, thresholds. |
| Artifact quality | Generated skills/commands/agents are not evaluated with local assertions. | Artifact checks exist for happy path only or do not report specific failure reasons. | Good artifacts pass and bad artifacts fail with expected reason codes such as `overbroad_trigger` and `privacy_leak`. | Artifact fixture names, eval command, expected pass/fail result, reason codes. |
| Distribution readiness | Package contents, metadata, and target distribution path are unknown or inconsistent. | Package dry-run or metadata checks exist, but target marketplace/package contents are not fully validated. | One primary distribution target is declared, shipped files are validated, and metadata/install vocabulary is checked for that target. | `npm pack --dry-run` or target-specific command, files included, metadata status, install/list/update docs. |

## Baseline Worksheet

Use this worksheet when scoring the current repo. Every area must include a score and notes.

| Area | Score (0-2) | Evidence command or file assertion | Notes |
| --- | ---: | --- | --- |
| Install health |  |  |  |
| Prompt surface |  |  |  |
| Recommendation ranking |  |  |  |
| Hook performance |  |  |  |
| Artifact quality |  |  |  |
| Distribution readiness |  |  |  |
| **Total** |  | Sum of six scores |  |

Baseline rules:

- Score the repository state being reviewed, not the intended future phase.
- A missing command, fixture, or file assertion caps the related area at 1.
- A known failure from the plan, such as an incomplete real-HOME install, must be recorded in notes even if a temp-HOME path passes.
- Do not award 2 for claims described only as "better", "high quality", "mature", or "useful"; the claim must be tied to a command, fixture, file assertion, or measured output.

## Evidence Map Coverage

Allowed scored area names: Install health, Prompt surface, Recommendation ranking, Hook performance, Artifact quality, Distribution readiness.

| Benchmark source | Exact scored area names supported |
| --- | --- |
| Anthropic Claude Code skills docs | Prompt surface |
| Anthropic Agent Skills overview/engineering post | Prompt surface |
| GitHub `gh skill` manual/changelog | Distribution readiness |
| Vercel `agent-skills` and React rules | Recommendation ranking, Artifact quality |
| Matt Pocock `skills` | Recommendation ranking, Hook performance, Artifact quality |
| Obra `superpowers` | Install health, Hook performance, Artifact quality |
| `skills.sh` directory | Distribution readiness |

## Review Gates

- Each benchmark source must map to at least one exact scored area name from this rubric.
- Each later phase must reference at least one fixture from `docs/benchmarks/fixtures.md` or state why no fixture applies.
- A reviewer must be able to validate plan structure without interpreting intent.
- A reviewer must be able to compute a baseline total and notes for all six scored areas.

## Stop Rules

- Do not implement Phase 1 until `docs/benchmarks/rubric.md` and `docs/benchmarks/fixtures.md` exist.
- Do not implement Phase 1 until plan-structure validation is documented or executable.
- If any checklist item in a later plan is missing `Task`, `Reason`, `Solution path`, or `Evidence`, stop plan approval until it is fixed.
- If a benchmark area receives 0, later work may proceed only when that phase explicitly targets the failing area or records why it is out of scope.
