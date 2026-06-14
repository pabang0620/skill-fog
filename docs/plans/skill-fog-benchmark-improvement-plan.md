# skill-fog Benchmark-Based Improvement Plan

Date: 2026-06-13
Status: Planning only. Implementation is blocked until Phase 0 is reviewed.
Repository: `pabang0620/skill-fog`

## Purpose

Plan phased improvements for `skill-fog` using only benchmark patterns that can be converted into local acceptance tests. No phase may rely on vague claims such as "better", "high quality", "mature", or "useful" unless the claim is tied to a command, fixture, file assertion, or measured output.

## Baseline Evidence

The current local repository state, refreshed on 2026-06-13, is:

| Item | Observed value | Reason it matters | Evidence command |
| --- | ---: | --- | --- |
| `SKILL.md` size | 419 lines, 13.8 KB | Prompt surface is large enough that progressive disclosure is justified. | `wc -l -c SKILL.md` |
| `hooks/stop.sh` size | 774 lines, 28.0 KB | Hook behavior is complex enough to require fixture tests and benchmark timing. | `wc -l -c hooks/stop.sh` |
| `bin/skill-fog` size | 984 lines, 34,578 bytes | CLI behavior needs command-level self-tests before new features are added. | `wc -l -c bin/skill-fog` |
| package contents | 9 files, 114,801 bytes | New runtime dirs such as `references/` or `scripts/` will not ship unless `package.json.files` changes. | `npm pack --dry-run` |
| Hook simulation | Creates `patterns.json` and `pending/*.json` in isolated `HOME` | The core repeated-pattern path works and must be preserved. | Temp-HOME transcript simulation |
| Real user install | 5 ok, 3 warnings, 1 failure | Actual `/home/pabang` install is incomplete and must not be treated as healthy. | `HOME=/home/pabang ./bin/skill-fog doctor` |

Current real-HOME install failure:

- Missing installed `~/.claude/skills/skill-fog/SKILL.md`.
- No `~/.claude/settings.json` hook state detected by doctor.
- CLI not found in PATH.
- Doctor remediation currently prints an unusable `bash /install.sh` path in this state.

## Benchmark Evidence Map

These sources justify review criteria only where they map to a local test. Popularity numbers are market evidence, not proof of correctness.

| Source | Accessed | Observed fact | Local criterion | Does not justify |
| --- | --- | --- | --- | --- |
| Anthropic Claude Code skills docs | 2026-06-13 | Skills can use supporting files and should keep top-level instructions focused. | `SKILL.md` must route to references/scripts and keep detailed code blocks out of the always-loaded surface. | Does not justify arbitrary line limits below official guidance. |
| Anthropic Agent Skills overview/engineering post | 2026-06-13 | Progressive disclosure is the core scaling pattern for skills. | Phase 2 must include a reference-loading table and behavior map. | Does not prove generated artifacts are good. |
| GitHub `gh skill` manual/changelog | 2026-06-13 | `gh skill` provides install/list/preview/publish/search/update vocabulary and is preview. | Phase 6 may borrow lifecycle vocabulary, but must not depend on `gh skill` unless chosen as the primary target. | Does not justify supporting every marketplace at once. |
| Vercel `agent-skills` | 2026-06-13 | `vercel-labs/agent-skills` had 27,873 stars. React rules are grouped by category/severity. | Phase 3 and 5 must attach category, severity, and expected evidence to each local rule. | Does not justify hook latency budgets. |
| Matt Pocock `skills` | 2026-06-13 | `mattpocock/skills` had 127,272 stars. Engineering skills emphasize TDD/diagnosis feedback loops. | Phase 0/1/5 must define fixtures before behavior changes. | Does not justify copying workflows verbatim. |
| Obra `superpowers` | 2026-06-13 | `obra/superpowers` had 226,373 stars. Planning/verification skills require evidence before completion claims. | Every phase checklist item must include Task, Reason, Solution path, and Evidence. | Does not decide skill-fog product scope. |
| `skills.sh` directory | 2026-06-13 | Skills are discoverable through metadata and install commands. | Phase 6 must define one primary distribution target and validate metadata for that target. | Does not justify broad marketplace work before package contents are correct. |

Source URLs:

- https://code.claude.com/docs/en/skills
- https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/
- https://cli.github.com/manual/gh_skill
- https://github.com/vercel-labs/agent-skills
- https://vercel.com/blog/introducing-react-best-practices
- https://github.com/mattpocock/skills
- https://github.com/obra/superpowers
- https://www.skills.sh/

## Required Checklist Schema

Every implementation checklist item must use this schema:

```md
- [ ] Task: <imperative, file/command-specific action>
  Reason: <risk or gap this removes>
  Solution path: <files, command, fixture, or schema to add/change>
  Evidence: <exact command, output, or file assertion proving completion>
```

Reason:

- A plain checkbox can hide assumptions.
- This schema forces each task to explain why it exists, how to solve it, and how to prove it.

Review rule:

- Any checklist item missing `Task`, `Reason`, `Solution path`, or `Evidence` fails plan review.
- Review gates are not implementation checklist items and must be written as plain bullets, not checkboxes.

## Phase 0: Benchmark Rubric and Fixture Contract

Goal: Define the rubric, fixture shapes, and stop rules used by every later phase.

Stop condition: Do not implement Phase 1 until the rubric file, fixture manifest, and plan-structure validation process exist. The script check is structural; manual review still verifies semantic specificity.

Checklist:

- [ ] Task: Create `docs/benchmarks/rubric.md`.
  Reason: The benchmark sources are currently evidence, but not a pass/fail standard.
  Solution path: Define six scored areas: install health, prompt surface, recommendation ranking, hook performance, artifact quality, and distribution readiness. Each area uses `0 = fail`, `1 = partial`, `2 = pass`.
  Evidence: A reviewer can score the current repo and produce a baseline total with notes for all six areas.

- [ ] Task: Create `docs/benchmarks/fixtures.md`.
  Reason: Later phases need shared fixture names and expected outputs instead of inventing tests per phase.
  Solution path: Document fixture path, owner phase, input shape, expected command, and expected assertion.
  Evidence: The manifest includes every fixture listed in the fixture contract below.

- [ ] Task: Define a plan-structure validation rule.
  Reason: Future plan edits could reintroduce abstract checklist items.
  Solution path: Add either a script plan, `scripts/check-plan-structure.sh`, or a documented manual review procedure that fails missing `Reason`, `Solution path`, or `Evidence` fields.
  Evidence: Running the script or manual procedure flags a deliberately malformed checklist item.

Fixture contract:

| Fixture | Used by | Input | Expected evidence |
| --- | --- | --- | --- |
| `fixtures/transcripts/claude-jsonl-v1.jsonl` | Phase 1 | Top-level `role=user` transcript shape | Pending proposal is created in temp HOME. |
| `fixtures/transcripts/claude-jsonl-v2.jsonl` | Phase 1 | Nested `type=user`, `message.role=user` transcript shape | Pending proposal is created in temp HOME. |
| `fixtures/transcripts/cursor-regression.jsonl` | Phase 1B | Transcript with existing cursor offset | Re-running hook does not increment old messages. |
| `fixtures/transcripts/small.jsonl` | Phase 1B/4 | 10 KB or about 20 user/assistant lines | Benchmark reports p50/p95. |
| `fixtures/transcripts/medium.jsonl` | Phase 1B/4 | 1 MB or about 2,000 lines | Benchmark reports p50/p95. |
| `fixtures/transcripts/large-incremental.jsonl` | Phase 1B/4 | 10 MB or about 20,000 lines with cursor near EOF | Incremental benchmark reports p50/p95. |
| `fixtures/patterns/ranking-basic.json` | Phase 3 | Repeated patterns plus obvious noise | Expected ranked output matches oracle. |
| `fixtures/patterns/privacy-risk.json` | Phase 3/5 | Secrets, emails, tokens, and benign patterns | Risk penalties and redactions appear. |
| `fixtures/artifacts/good-skill.json` | Phase 5 | Valid generated skill draft | Artifact eval passes. |
| `fixtures/artifacts/bad-overbroad-skill.json` | Phase 5 | Trigger is too broad | Artifact eval fails with `overbroad_trigger`. |
| `fixtures/artifacts/bad-secret-leak.json` | Phase 5 | Example contains secret-like text | Artifact eval fails with `privacy_leak`. |

Review gate:

- Each benchmark source maps to at least one scored area name in `docs/benchmarks/rubric.md`.
- Each later phase references at least one fixture or states why no fixture applies.
- A reviewer can validate the structural checklist schema with `scripts/check-plan-structure.sh`.
- A reviewer can manually reject abstract `Reason`, `Solution path`, or `Evidence` values that pass structural checks but lack concrete files, commands, fixtures, outputs, or assertions.

Completion evidence:

- `docs/benchmarks/rubric.md` exists.
- `docs/benchmarks/fixtures.md` exists.
- Plan-structure validation is documented or executable.

## Phase 1A: Isolated Install and Doctor Self-Test

Goal: Prove install/doctor/uninstall behavior without touching the real user environment.

Benchmark basis:

- GitHub skill lifecycle vocabulary justifies install/list/update-style checks.
- Obra verification style requires fresh command evidence before any health claim.

Stop condition: Do not run write operations against `/home/pabang` until temp-HOME install and uninstall checks pass.

Checklist:

- [ ] Task: Fix `skill-fog doctor` remediation output for missing `SKILL.md`.
  Reason: The current output can point to `bash /install.sh`, which is not a runnable local command.
  Solution path: Resolve the package root from `BASH_SOURCE` or symlink target and print either `npm install -g skill-fog` or `bash <repo>/install.sh`.
  Evidence: `HOME="$(mktemp -d)" ./bin/skill-fog doctor` prints no `bash /install.sh` string and includes one runnable install command.

- [ ] Task: Add temp-HOME install self-test.
  Reason: Real HOME install testing can mutate user files and hide irreversible cleanup risk.
  Solution path: Add `skill-fog doctor --self-test` or `scripts/self-test-install.sh` that creates a temp HOME, runs install, checks files, and removes the temp dir.
  Evidence: The self-test exits 0 and reports installed `SKILL.md`, hook file, settings hook, CLI link, and patterns directory inside temp HOME.

- [ ] Task: Add install idempotency check.
  Reason: Users may reinstall; duplicate hooks would make stop processing run multiple times.
  Solution path: Run `install.sh` twice in temp HOME and count matching Stop hook commands in settings.
  Evidence: The second install leaves exactly one skill-fog Stop hook command.

- [ ] Task: Add uninstall idempotency check in temp HOME.
  Reason: Uninstall can remove data and links; repeat uninstall must not fail or touch real files.
  Solution path: Run uninstall twice in temp HOME using non-interactive flags or a test harness that answers prompts safely.
  Evidence: Both runs exit 0, and temp HOME contains no skill-fog hook while preserving data when `--keep-data` or equivalent is requested.

- [ ] Task: Document exact doctor status meanings.
  Reason: Users need to distinguish failure, warning, and expected first-run states.
  Solution path: Add README or `references/troubleshooting.md` table for each doctor check.
  Evidence: Documentation includes every current doctor item: JSON tool, python3, storage dir, pending dir, patterns file, hook executable, installed SKILL.md, settings hook, PATH.

Review gate:

- Self-test never writes outside temp HOME.
- Doctor remediation contains executable commands.
- Idempotency checks prove no duplicate hook registration.

Completion evidence:

- `bash -n install.sh uninstall.sh hooks/stop.sh bin/skill-fog`
- `skill-fog doctor --self-test` or equivalent temp-HOME script
- `grep -R "/install.sh" test-output` returns no invalid remediation path.

## Phase 1B: Hook Fixture and Performance Baseline

Goal: Measure current hook behavior before refactoring or scoring changes.

Reason for splitting from Phase 4:

- Scoring and progressive disclosure can change hook cost or behavior.
- Current hook already includes cursor locking, transcript scanning, per-message updates, threshold checks, and a 50-message cap.
- Baseline first prevents later optimizations from hiding regressions.

Stop condition: Do not begin Phase 2 or Phase 3 until hook fixture simulation and baseline timing are recorded.

Checklist:

- [ ] Task: Add transcript fixture simulation for both supported Claude JSONL shapes.
  Reason: `hooks/stop.sh` supports two transcript structures and either can regress.
  Solution path: Use `fixtures/transcripts/claude-jsonl-v1.jsonl` and `claude-jsonl-v2.jsonl` in a temp HOME harness.
  Evidence: Each fixture creates one expected pattern and one expected pending file.

- [ ] Task: Add cursor regression fixture.
  Reason: Reprocessing old transcript lines would inflate counts and create false recommendations.
  Solution path: Run hook twice with `fixtures/transcripts/cursor-regression.jsonl` and assert the second run does not increment old messages.
  Evidence: `patterns.json` count is unchanged on the second run.

- [ ] Task: Record baseline timing for small, medium, and large fixtures.
  Reason: Future hook changes need a before/after comparison.
  Solution path: Add `scripts/bench-hook.sh` or documented command using 3 warmups and 30 measured runs per fixture.
  Evidence: Baseline table records fixture size, line count, p50, p95, max, machine info, and date.

- [ ] Task: Define warning and failure thresholds after baseline measurement.
  Reason: A threshold chosen before measuring can be arbitrary.
  Solution path: Use baseline to set a first budget. Initial candidate: warn if a single hook run exceeds 1000 ms; fail benchmark if p95 exceeds 2000 ms.
  Evidence: `docs/benchmarks/hook-baseline.md` records final threshold and why it was chosen.

Review gate:

- Fixture simulation proves pattern creation, pending creation, and cursor non-reprocessing.
- Performance baseline includes run count, warmup count, fixture sizes, and timing method.
- No benchmark logs contain raw secrets or unredacted private examples.

Completion evidence:

- `scripts/bench-hook.sh` or documented equivalent.
- `docs/benchmarks/hook-baseline.md`.
- Temp-HOME hook fixture assertions pass.

## Phase 2: Progressive Disclosure Refactor

Goal: Move detailed procedures out of the always-loaded skill surface without changing behavior.

Benchmark basis:

- Anthropic sources justify supporting files and progressive disclosure.
- The local baseline justifies this because `SKILL.md` is 419 lines and includes long code blocks.

Stop condition: Do not change generation behavior until the behavior matrix maps each current `SKILL.md` section to a new home and a verification method.

Target structure:

```text
skill-fog/
├── SKILL.md
├── references/
│   ├── pattern-scoring.md
│   ├── artifact-generation.md
│   ├── privacy-and-redaction.md
│   └── troubleshooting.md
├── scripts/
│   ├── normalize-message.py
│   ├── score-patterns.py
│   └── self-test.sh
└── evals/
    ├── trigger-cases.json
    └── artifact-quality-cases.json
```

Required behavior matrix:

| Current behavior | Current location | New home | Verification |
| --- | --- | --- | --- |
| Session-start pending check | `SKILL.md` session start section | `SKILL.md` router + `references/artifact-generation.md` | Temp-HOME pending fixture prompts exactly one proposal. |
| 5-message threshold check | `SKILL.md` core behavior | `references/pattern-scoring.md` | Trigger fixture produces same `THRESHOLD_MET` decision. |
| Later/skip handling | `SKILL.md` STEP B | `references/artifact-generation.md` | `patterns.json` remains `active`; pending file has `snoozed_at`. |
| Reject handling | `SKILL.md` STEP B | `references/artifact-generation.md` | `patterns.json` becomes `rejected`; pending file removed. |
| Skill/command/agent preview | `SKILL.md` STEP D | `references/artifact-generation.md` | Preview contains required sections by artifact type. |
| Accept handling | `SKILL.md` STEP F | `references/artifact-generation.md` | Generated artifact path exists; pattern status becomes `accepted`. |

Checklist:

- [ ] Task: Replace long code blocks in `SKILL.md` with references to scripts or reference docs.
  Reason: Long embedded procedures increase always-loaded context and make changes harder to test.
  Solution path: Move normalization, status update, and generation details to `scripts/` or `references/`.
  Evidence: `SKILL.md` contains no Python/Bash block longer than 20 lines.

- [ ] Task: Add a reference-loading table to `SKILL.md`.
  Reason: Progressive disclosure only works if the model knows which file to open for each task.
  Solution path: Add table with task, file, and load condition.
  Evidence: Table includes pending review, scoring, artifact generation, privacy/redaction, and troubleshooting.

- [ ] Task: Replace fixed 120-180 line target with behavior-based prompt budget.
  Reason: Official guidance does not justify that exact range, and line counts alone do not prove lower context cost.
  Solution path: Require `SKILL.md` to contain only triggers, routing, safety rules, and reference-loading; record before/after line and byte count.
  Evidence: Before/after table appears in Phase 2 notes.

- [ ] Task: Update package contents for new runtime files.
  Reason: `package.json.files` currently omits `references/`, `scripts/`, and `evals/`.
  Solution path: Add required runtime directories to `package.json.files`, excluding non-runtime benchmark outputs if needed.
  Evidence: `npm pack --dry-run` lists every file required by `SKILL.md`.

Review gate:

- Behavior matrix has one row per current skill behavior.
- Every moved detail has a new file path.
- Temp-HOME state-transition checks cover later, reject, and accept.

Completion evidence:

- `wc -l -c SKILL.md` before/after.
- `npm pack --dry-run`.
- Phase 1 hook fixture tests still pass.

## Phase 3: Deterministic Pattern Scoring

Goal: Rank eligible repeated patterns using deterministic, explainable scoring.

Benchmark basis:

- Vercel justifies category/severity/explanation structure, not the specific scoring math.
- Matt Pocock/Obra justify fixture-first feedback loops.

Stop condition: Do not use scoring for live recommendations until fixtures define expected rankings.

Eligibility gate:

- `count >= 3`.
- `len(sessions) >= 2`.
- `status == "active"`.
- Message survives privacy redaction and noise filters.

Scoring output schema:

```json
{
  "pid": "string",
  "eligible": true,
  "total_score": 0,
  "suggested_type": "skill|command|agent|unknown",
  "confidence": "high|medium|low",
  "recommendation": "auto_propose|review_required|suppress",
  "components": {
    "frequency": { "points": 0, "max": 25, "evidence": "count value" },
    "session_spread": { "points": 0, "max": 20, "evidence": "session count" },
    "recency": { "points": 0, "max": 15, "evidence": "last_seen age" },
    "actionability": { "points": 0, "max": 20, "evidence": "verb/object/artifact signals" },
    "artifact_fit": { "points": 0, "max": 20, "evidence": "classifier rule id" },
    "noise_penalty": { "points": 0, "min": -30, "evidence": "noise rule id or none" },
    "privacy_penalty": { "points": 0, "min": -50, "evidence": "redaction rule id or none" }
  },
  "reasons": ["string"]
}
```

Recommendation thresholds:

- `auto_propose`: eligible and `total_score >= 70`, no privacy penalty, confidence high or medium.
- `review_required`: eligible and `40 <= total_score < 70`, or privacy penalty was applied but redaction succeeded.
- `suppress`: not eligible, `total_score < 40`, noise penalty <= -30, or privacy penalty <= -50.

Checklist:

- [ ] Task: Add `fixtures/patterns/ranking-basic.json` with expected sorted output.
  Reason: Without an oracle, scoring can be tuned subjectively.
  Solution path: Include at least 10 patterns: 4 clear positives, 3 review-required, 3 suppress cases.
  Evidence: `score-patterns.py --fixture fixtures/patterns/ranking-basic.json` matches the expected order and recommendation labels.

- [ ] Task: Add `fixtures/patterns/privacy-risk.json`.
  Reason: Scoring must not recommend artifacts from secrets or sensitive examples.
  Solution path: Include token-like strings, emails, DB URLs, and benign repeated prompts.
  Evidence: Output contains redaction reasons and no raw secret-like values.

- [ ] Task: Implement deterministic scoring before any LLM clustering.
  Reason: Deterministic scoring is testable offline and preserves local-first privacy.
  Solution path: Use local JSON parsing and rule IDs; defer LLM clustering to a future phase only if fixtures expose a concrete limitation.
  Evidence: Scoring works offline with no network and no API key.

- [ ] Task: Add manual override semantics.
  Reason: Users must be able to accept patterns with clear repeated-workflow evidence that scoring underrates or reject noisy ones.
  Solution path: Define override fields in pending JSON, such as `manual_decision`, `desired_type`, and `reviewed_at`.
  Evidence: Fixture with manual override changes recommendation without changing raw score.

Review gate:

- Score output includes component evidence for every point or penalty.
- Fixture oracle catches false positives and privacy-risk suppressions.
- No live prompt history is sent to an external service.

Completion evidence:

- `scripts/score-patterns.py --fixture fixtures/patterns/ranking-basic.json`.
- `scripts/score-patterns.py --fixture fixtures/patterns/privacy-risk.json`.
- Existing `/home/pabang/.skill-fog/patterns.json` can be scored read-only with no mutation.

## Phase 4: Hook Performance Guardrails

Goal: Turn Phase 1B baseline into ongoing performance checks.

Benchmark basis:

- Phase 1B provides local hook timing evidence.
- Vercel's category/severity structure justifies labeling performance failures by impact.

Stop condition: Do not add new hook work unless benchmark output shows p95 remains under the accepted budget.

Metrics:

- Hook wall time.
- Transcript bytes read.
- New lines processed.
- User messages processed.
- JSON parse failures.
- Pattern update time.
- Pending generation time.
- Cursor lock wait time.

Checklist:

- [ ] Task: Add structured benchmark output.
  Reason: Plain timing logs are hard to compare across changes.
  Solution path: Emit JSON with fixture name, run count, warmup count, p50, p95, max, machine info, and git SHA.
  Evidence: `scripts/bench-hook.sh --json` outputs valid JSON matching documented schema.

- [ ] Task: Add performance budget enforcement.
  Reason: A benchmark that never fails cannot prevent regressions.
  Solution path: Read thresholds from `docs/benchmarks/hook-baseline.md` or config and exit nonzero on p95 failure.
  Evidence: Deliberately low threshold causes benchmark failure with `performance_budget_exceeded`.

- [ ] Task: Add privacy-safe debug logging.
  Reason: Benchmark and diagnostic logs must not leak raw prompt examples.
  Solution path: Log counts, sizes, hashes, and redaction rule IDs instead of raw messages.
  Evidence: Running benchmark on `privacy-risk.json` produces no raw token/email/DB URL.

Review gate:

- Benchmarks run without Claude Code.
- Failure output names the fixture and exceeded threshold.
- Benchmark JSON is stable enough for CI or local comparison.

Completion evidence:

- `scripts/bench-hook.sh --json`.
- Failure-path test using deliberately low threshold.
- Hook fixture tests still pass.

## Phase 5: Artifact Quality Evals

Goal: Evaluate generated skill/command/agent drafts with fixture oracles before they are trusted.

Benchmark basis:

- Anthropic `skill-creator` justifies iterative evals.
- Obra/Matt Pocock workflows justify behavior-oriented tests and explicit failure reasons.

Stop condition: Do not auto-install generated artifacts. Generated output remains a draft until eval passes and user approves.

Artifact eval schema:

```json
{
  "case_id": "string",
  "input_pattern": {
    "canonical": "string",
    "examples": ["string"],
    "count": 3,
    "sessions": ["s1", "s2"]
  },
  "expected_artifact_type": "skill|command|agent",
  "required_sections": ["trigger", "workflow", "completion_evidence"],
  "forbidden_patterns": ["raw_secret", "overbroad_trigger", "production_destructive_action"],
  "privacy_expectation": "redacted|no_sensitive_data",
  "expected_result": "pass|fail",
  "expected_reason": "string"
}
```

Checklist:

- [ ] Task: Add positive artifact fixture.
  Reason: The eval runner needs one known-good artifact to prevent rejecting all outputs.
  Solution path: Create `fixtures/artifacts/good-skill.json` with a narrow trigger and completion evidence.
  Evidence: `scripts/run-evals.sh --case good-skill` returns pass.

- [ ] Task: Add one fixture per critical failure class.
  Reason: A rubric cannot protect users unless it catches known bad outputs.
  Solution path: Add overbroad trigger, leaked secret, wrong artifact type, and missing completion behavior cases.
  Evidence: Each bad fixture fails with the expected `expected_reason`.

- [ ] Task: Define artifact pass threshold.
  Reason: Reviewers need a decision rule, not subjective approval.
  Solution path: Critical failures are automatic fail; noncritical rubric score must be at least 80/100.
  Evidence: Eval output includes score, critical failures, warnings, and final result.

- [ ] Task: Require review-required state for low-confidence artifacts.
  Reason: A low-confidence draft should not be installed silently.
  Solution path: Add `review_required` state and require user approval before writing to `~/.claude`.
  Evidence: Low-confidence fixture produces a draft file path and no installed artifact path.

Review gate:

- Eval failures identify trigger, privacy, type, or completion issue.
- At least one red-team fixture catches a bad generation.
- Passing artifacts still require user approval before installation.

Completion evidence:

- `scripts/run-evals.sh`.
- Eval JSON output with pass/fail reasons.
- Draft-only behavior for low-confidence artifacts.

## Phase 6: Distribution Readiness

Goal: Make the package installable and discoverable through one chosen primary target.

Default first-pass target:

- Primary: npm and GitHub README.
- Secondary documentation: skills.sh-compatible metadata if it does not require a separate runtime format.
- Deferred: `gh skill publish`, Claude plugin marketplace, Codex/Gemini/Cursor compatibility.

Reason:

- The current package already ships through npm.
- `gh skill` is preview and should not be a blocker.
- Multiple marketplace targets would mix incompatible validators and delay core stability.

Stop condition: Do not add a marketplace target unless package contents, install self-test, and privacy docs pass first.

Checklist:

- [ ] Task: Update `package.json.files` for new runtime files.
  Reason: Phase 2 introduces directories that npm will otherwise omit.
  Solution path: Include `references/`, required `scripts/`, and required eval fixtures only if they are needed at runtime or validation time.
  Evidence: `npm pack --dry-run` lists every file referenced by `SKILL.md`.

- [ ] Task: Add release checklist.
  Reason: Manual release steps are easy to skip and can publish broken packages.
  Solution path: Create `CHANGELOG.md` and `docs/release-checklist.md` with syntax check, self-test, hook fixtures, benchmarks, evals, and `npm pack --dry-run`.
  Evidence: Checklist contains exact commands and expected pass criteria.

- [ ] Task: Add README install and privacy verification section.
  Reason: Users need to know what is installed and what data stays local.
  Solution path: Document npm install, curl install, uninstall, doctor, self-test, and privacy/redaction behavior.
  Evidence: README has commands for install, verify, uninstall, and privacy inspection.

- [ ] Task: Add one discoverability metadata file only after selecting its schema.
  Reason: "Marketplace-compatible" is not actionable without a target schema.
  Solution path: For first pass, create only metadata required by npm/GitHub README or a documented skills.sh-compatible file if schema is confirmed.
  Evidence: Metadata file includes name, description, version, license, repository, install command, privacy note, and supported host.

Review gate:

- One primary distribution target is named.
- Every published file referenced by docs is included in `npm pack --dry-run`.
- No deferred marketplace is treated as a blocker.

Completion evidence:

- `npm pack --dry-run`.
- `skill-fog doctor --self-test`.
- Release checklist commands pass.

## Cross-Phase Review Rules

Before implementing each phase:

- [ ] Task: Identify the benchmark criterion used by the phase.
  Reason: Prevents implementation based on popularity or preference alone.
  Solution path: Link the phase to `docs/benchmarks/rubric.md`.
  Evidence: Phase notes cite the rubric row.

- [ ] Task: Identify the fixture or explicit no-fixture reason.
  Reason: Prevents untestable changes.
  Solution path: Link to `docs/benchmarks/fixtures.md`.
  Evidence: Phase notes cite fixture path or explain why no fixture applies.

- [ ] Task: Identify preserved behavior.
  Reason: Prevents hidden regressions while refactoring.
  Solution path: List state files, commands, prompts, or generated paths that must remain compatible.
  Evidence: Pre/post check records unchanged behavior.

After implementing each phase:

- [ ] Task: Record command evidence in phase notes.
  Reason: Completion claims must be backed by fresh output.
  Solution path: Add command, exit code, and short output summary to the phase notes.
  Evidence: Reviewer can reproduce or inspect the evidence.

- [ ] Task: Run package and syntax checks.
  Reason: Bash/packaging failures can break install even when docs look correct.
  Solution path: Run `bash -n`, self-tests, fixture tests, and `npm pack --dry-run`.
  Evidence: All commands exit 0 or failed commands have linked follow-up tasks.

## Recommended Execution Order

1. Phase 0: Benchmark Rubric and Fixture Contract
2. Phase 1A: Isolated Install and Doctor Self-Test
3. Phase 1B: Hook Fixture and Performance Baseline
4. Phase 2: Progressive Disclosure Refactor
5. Phase 3: Deterministic Pattern Scoring
6. Phase 4: Hook Performance Guardrails
7. Phase 5: Artifact Quality Evals
8. Phase 6: Distribution Readiness

Reason:

- Phase 0 makes every later review objective.
- Phase 1A prevents real-HOME install/uninstall damage.
- Phase 1B records behavior and timing before refactors.
- Phase 2 reduces prompt surface only after baseline behavior is protected.
- Phase 3 changes recommendation behavior only after fixtures exist.
- Phase 4 prevents later scoring or parsing work from slowing the hook.
- Phase 5 verifies generated artifacts before trust or installation.
- Phase 6 improves adoption only after package contents and local validation are stable.

## Default Decisions for First Pass

- Target Claude Code first.
  Reason: Current implementation writes to `~/.claude` and installs Claude Code hooks.

- Treat Codex, Gemini, Cursor, and other hosts as future compatibility work.
  Reason: Supporting multiple hosts changes paths, hook models, and generated artifact formats.

- Use deterministic local heuristics first.
  Reason: Deterministic rules can be tested offline and preserve private prompt history.

- Do not use an LLM for clustering or artifact-fit scoring until fixture evals show a concrete failure mode.
  Reason: LLM scoring would add privacy, cost, and reproducibility risks.

- Generate artifacts as drafts until explicit user approval.
  Reason: Generated skills/commands/agents can alter future agent behavior.

- Stage distribution as npm/GitHub README first, then optional marketplace metadata.
  Reason: npm is already the current distribution channel and can be validated with `npm pack --dry-run`.

## Non-Goals for the First Implementation Pass

- No cloud sync.
- No server-side analytics.
- No automatic publication of generated skills.
- No external API call using private prompt history by default.
- No real-HOME install/uninstall mutation without explicit approval.
- No dependency-heavy rewrite until Bash/Python fixtures expose a concrete limit.
