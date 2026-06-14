# skill-fog Benchmark Fixtures

Date: 2026-06-13
Status: Phase 0 benchmark artifact
Source plan: `docs/plans/skill-fog-benchmark-improvement-plan.md`

## Purpose

This manifest defines the fixture contract for later benchmark phases. Fixtures do not need to exist in Phase 0, but later phases must use these paths and assertions or update this manifest with a reviewed reason.

Required fields for every fixture:

- Fixture path
- Owner phase
- Input shape
- Expected command
- Expected assertion

## Fixture Manifest

| Fixture path | Owner phase | Input shape | Expected command | Expected assertion |
| --- | --- | --- | --- | --- |
| `fixtures/transcripts/claude-jsonl-v1.jsonl` | Phase 1 | JSONL transcript with top-level `role=user` messages. | Run the hook fixture simulation in a temp HOME against this transcript. | One expected pattern is recorded and one pending proposal is created in temp HOME. |
| `fixtures/transcripts/claude-jsonl-v2.jsonl` | Phase 1 | JSONL transcript with nested `type=user` and `message.role=user` messages. | Run the hook fixture simulation in a temp HOME against this transcript. | One expected pattern is recorded and one pending proposal is created in temp HOME. |
| `fixtures/transcripts/cursor-regression.jsonl` | Phase 1B | JSONL transcript with an existing cursor offset and old messages before the cursor. | Run the hook simulation twice in the same temp HOME with the cursor state preserved. | The second run does not increment counts from old messages. |
| `fixtures/transcripts/small.jsonl` | Phase 1B/4 | Synthetic transcript with 20 lines and 2,031 bytes. | Run the hook benchmark with warmups and measured iterations. | Benchmark output reports p50 and p95 for the small fixture. |
| `fixtures/transcripts/medium.jsonl` | Phase 1B/4 | Synthetic transcript with 180 lines and 20,600 bytes. | Run the hook benchmark with warmups and measured iterations. | Benchmark output reports p50 and p95 for the medium fixture. |
| `fixtures/transcripts/large-incremental.jsonl` | Phase 1B/4 | Synthetic transcript with 900 lines and 126,676 bytes; the benchmark initializes a cursor before the final 100 lines for every warmup and measured run. | Run the incremental hook benchmark with a fresh temp HOME copied from the same cursor template for each warmup and measured iteration. | Incremental benchmark output reports p50 and p95 for the large fixture, and each iteration must advance the cursor from the template offset. |
| `fixtures/patterns/ranking-basic.json` | Phase 3 | Repeated patterns plus obvious noise. | Run the ranking evaluator against the fixture and oracle. | Ranked output matches the expected oracle order. |
| `fixtures/patterns/privacy-risk.json` | Phase 3/5 | Secrets, emails, tokens, and benign repeated patterns. | Run ranking and artifact/privacy evaluators against the fixture. | Risk penalties are applied and secret-like values are redacted. |
| `fixtures/artifacts/good-skill.json` | Phase 5 | Valid generated skill draft. | Run the artifact evaluator against the fixture. | Artifact evaluation passes. |
| `fixtures/artifacts/bad-overbroad-skill.json` | Phase 5 | Generated skill draft with a trigger that is too broad. | Run the artifact evaluator against the fixture. | Artifact evaluation fails with `overbroad_trigger`. |
| `fixtures/artifacts/bad-secret-leak.json` | Phase 5 | Generated skill draft whose example contains secret-like text. | Run the artifact evaluator against the fixture. | Artifact evaluation fails with `privacy_leak`. |

## Owner Phase Gates

| Owner phase | Required fixture use before completion |
| --- | --- |
| Phase 1 | Validate both supported Claude JSONL transcript shapes in temp HOME. |
| Phase 1B | Validate cursor non-reprocessing and record hook timing for small, medium, and large transcript fixtures. |
| Phase 3 | Validate recommendation ranking with a basic ranking oracle and privacy-risk penalties. |
| Phase 4 | Re-run timing fixtures and compare p50/p95 against the baseline threshold. |
| Phase 5 | Validate artifact pass/fail behavior and privacy leak detection. |

Review gate:

- Each later phase references at least one fixture in this manifest or states why no fixture applies.
- No benchmark log may include raw secrets or unredacted private examples.
- Fixture commands must use temp HOME when they can write skill-fog state.
- The current timing fixtures are small synthetic coverage fixtures, not MB-scale load fixtures. Do not use them to claim production-scale throughput without adding larger fixtures and updating this manifest.

## Plan-Structure Validation

Phase 0 uses `scripts/check-plan-structure.sh` as a structural validation script and this manual procedure for semantic review. The script intentionally checks implementation checklist shape only: outside fenced code, every implementation checkbox must begin with `Task:` and include non-empty `Reason:`, `Solution path:`, and `Evidence:` fields. Review gates are plain bullets, not checkboxes.

Semantic limits:

- The script does not decide whether a reason is meaningful.
- The script does not decide whether evidence is strong enough.
- The script does not check that referenced files, commands, fixtures, or outputs already exist.
- Manual review must reject abstract wording that lacks a concrete file, command, fixture, schema, output, or assertion.

Checklist item schema:

```md
- [ ] Task: <imperative, file/command-specific action>
  Reason: <risk or gap this removes>
  Solution path: <files, command, fixture, or schema to add/change>
  Evidence: <exact command, output, or file assertion proving completion>
```

Manual procedure:

1. Run `bash scripts/check-plan-structure.sh docs/plans/skill-fog-benchmark-improvement-plan.md`.
2. Confirm the script reports the number of implementation checklist items validated.
3. Open the plan being reviewed.
4. For each implementation checklist item, verify that `Reason:`, `Solution path:`, and `Evidence:` identify concrete files, commands, fixtures, schemas, outputs, or assertions.
5. Fail plan review if any required field is missing, empty, or replaced with abstract wording.
6. Confirm that manual semantic review can flag this deliberately malformed checklist item even though the script will already fail its missing structural field:

```md
- [ ] Task: Improve benchmark quality.
  Reason: Benchmarks should be better.
  Evidence: Reviewer agrees.
```

Expected manual result for the malformed item:

- Fail: missing `Solution path`.
- Fail: `Reason` is abstract and does not identify a risk or gap.
- Fail: `Evidence` is subjective and does not identify a command, output, file assertion, or measured result.

## Stop Rules

- Do not implement Phase 1 until this manifest exists and includes every fixture from the fixture contract.
- Do not approve a later phase if it introduces new fixture names without updating this manifest.
- Stop plan approval when a checklist item is missing `Task`, `Reason`, `Solution path`, or `Evidence`.
- Stop plan approval when a review gate is written as a checkbox instead of a plain bullet.
- Stop benchmark approval when the expected assertion cannot be checked from a command, fixture, file assertion, or measured output.
