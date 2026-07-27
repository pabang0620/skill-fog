# Changelog

All notable changes to this package are documented here.

## Unreleased

## 2.5.0

### Added
- **Claude Code plugin distribution**: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `hooks/hooks.json` let users install via `/plugin marketplace add pabang0620/skill-fog` followed by `/plugin install skill-fog`, with hooks activating automatically.
- **GitHub Actions CI**: a release-checklist workflow runs JSON/shell/Python syntax checks, version consistency checks, the doctor self-test, hook assertions, and the new regression tests on every push and pull request.
- **Regression tests**: `scripts/test-session-start.sh` and `scripts/test-privacy-redaction.sh` cover the SessionStart hook and the secret-masking pipeline.
- **MIT LICENSE** file added to the repository and npm package.
- **Local path redaction**: `mask_secrets` now masks local filesystem paths (`/home/...`, `/Users/...`, `/var/...`, `/tmp/...`) with `[LOCAL_PATH]` before anything is written to disk.
- **npm `preuninstall` hook**: `preuninstall.js` runs automatic cleanup on `npm uninstall`, backing up removed files with a timestamp and preserving `~/.skill-fog/` data by default.

### Changed
- `SKILL.md` and its references moved from the repository root into `skills/skill-fog/`.
- The installer no longer auto-edits `~/.claude/CLAUDE.md`; it now prints manual opt-in guidance instead.
- README rewritten in English with a plugin-first install flow.
- Bundled evaluator agents (`skill-evaluator`, `agent-evaluator-v2`) translated to English, keeping their Korean trigger phrases.
- The noise-skip debug log now records message length only instead of a text preview.
- Docs scrubbed of personal paths and machine-specific information.
- Corrected "runs at session end" wording to "runs at the end of each assistant turn" throughout `hooks/stop.sh`, `SKILL.md`, and `references/privacy-and-redaction.md`.

### Fixed
- `uninstall.sh` now backs up removed agents and skills before deletion.
- Fixed an unquoted heredoc in `uninstall.sh`.
- `fixtures/patterns/ranking-basic.json` was missing a deterministic `now` anchor for recency scoring; added and documented in the fixture schema.
- Version sync verified across `package.json`, `skills/skill-fog/SKILL.md`, `skill-fog.metadata.json`, and `.claude-plugin/plugin.json` (all `2.5.0`).
- Missing `python3` now prints a warning to stderr instead of failing silently.
- Stale reference docs corrected: removed the ghost "Five-message check" mention and corrected the pending-sort description.

## 2.4.0

### Changed
- **Internationalization**: all user-facing output is now English by default, and SKILL.md/references instruct Claude to **respond in the same language the user is using**. English users now get English proposals; Korean users still get Korean. Korean input trigger words (`나중에`, `거부`, etc.) remain recognized.
- `SKILL.md`: fully translated to English; added an explicit language-mirroring rule.
- `hooks/session-start.sh`: injected proposal text translated to English with a "respond in the user's language" reminder.
- `references/pattern-scoring.md`, `references/artifact-generation.md`: proposal/preview/completion templates translated to English.
- `install.sh` / `uninstall.sh`: the CLAUDE.md trigger block is now English (marker `# skill-fog: pattern detection`). Install migrates the legacy Korean block; uninstall removes both old and new markers.

### Fixed
- `references/privacy-and-redaction.md`: the "later/skip" section no longer contradicts snooze — it now reflects that a proposed pattern is already `snoozed` and is not re-queued.

### Example
```
[skill-fog] You have 3 repeated pattern(s) pending review.

1. "deploy the frontend build to staging" - 4x, 3 sessions -> recommended: command (resume trigger)
2. "summarize the overall scope of the project" - 3x, 2 sessions -> recommended: command (context lookup)
3. "find every place that calls the old API" - 3x, 3 sessions -> recommended: agent (needs analysis)

Proceed with the recommendations? (Enter or "auto")
```

## 2.3.1

### Fixed
- **Propose-once snooze**: once a pattern is proposed at session start, it is immediately moved to `snoozed` and its pending file removed, so ignoring a proposal no longer re-asks every session. `stop.sh` excludes `snoozed` from pending re-promotion. Revisit anytime via `/skill-fog`.

### Behavior change

| Behavior | Before 2.3.1 | 2.3.1+ |
|---|---|---|
| Ignore the proposal | Asked again next session | Not asked again |
| Explicitly skip ("later") | Re-queued for next session | Stays snoozed |
| Explicitly reject | Marked rejected, never again | Same |
| Want to revisit later | (no path) | `/skill-fog` shows snoozed patterns |

## 2.3.0

### Added
- **System noise filtering** (`hooks/stop.sh`): Claude Code internal messages (`[request interrupted]`, `<local-command-stdout>`, `this session is being continued`, etc.) are filtered at collection time.
- **Smart type recommendation**: each pending pattern is classified into a recommended skill/command/agent with a one-line reason; press Enter to accept all.
- **Bundled evaluators**: `skill-evaluator` and `agent-evaluator-v2` are included in the package and installed to `~/.claude/agents/`.

### Fixed
- `uninstall.sh`: now removes the bundled evaluator agents on uninstall.

### Example (historical example, Korean - proposals are localized to the user's language)
```
[skill-fog] 반복 패턴 3개를 자동화할 수 있어요.

1. "계속진행해줘 실수로 취소했어" (3회/3세션) - 추천: command (재개 트리거)
2. "서버에 반영해야할 파일 뭐 더라?" (3회/2세션) - 추천: command (현재 상태 조회)
3. "일단 사업의 전반적인 이해를..." (3회/3세션) - 추천: command (컨텍스트 파악)

추천대로 진행할까요? (엔터 또는 "자동")
개별 변경: "1 스킬, 3 안함" 처럼 입력
```

## 2.2.0

### Added
- **STEP E.5 — 자동 품질 개선 루프**: 아티팩트 생성 직후 사용자에게 1회 승인 요청. 승인 시 `agent-evaluator-v2`가 생성된 파일을 100점 척도로 평가하고 점수 < 80이면 라인 단위 개선안을 자동 적용. skill/command/agent 모든 타입 지원.
- `references/artifact-generation.md`: 품질 개선 루프 절차, 에이전트 호출 방식, 점수 임계값(80), 완료 출력 형식 명시.
- `SKILL.md`: STEP E.5 단계 추가 (STEP E와 STEP F 사이).

## 2.1.0

### Added
- **SessionStart hook** (`hooks/session-start.sh`): fires at every Claude Code session start (`startup` / `resume`) and injects pending patterns into Claude's context before the first user message. Auto-proposal is now deterministic — no longer dependent on LLM attention or message-count heuristics.
- `install.sh`: registers the SessionStart hook alongside the existing Stop hook. `register_single_hook()` generic function prevents duplicate registration.
- `uninstall.sh`: removes the SessionStart hook entry and deletes `session-start.sh`. `remove_hook_by_cmd()` generic function handles both hooks.
- `bin/skill-fog doctor`: checks that `session-start.sh` exists and is executable, and that the SessionStart hook is registered in `~/.claude/settings.json`.
- `bin/skill-fog doctor --self-test`: verifies SessionStart hook count after install (expect 1) and after uninstall (expect 0).

### Changed
- `SKILL.md`: removed "5-message check" activation condition. Activation is now event-driven: `[skill-fog] 검토 대기 중인 반복 패턴 N개가 있습니다.` appears in context when the SessionStart hook fires.
- `~/.claude/CLAUDE.md` block updated to reflect hook-based injection (install.sh writes this on install).
- `package.json` version: `2.0.6` → `2.1.0`.

## 2.0.6

- Published `skill-fog@2.0.6` to npm as the current `latest` dist-tag.
- Added push-protection-safe fixture placeholders for release packaging checks.
- Prepared release-readiness harness assets for npm package distribution.
- Fixed npm package metadata by using the canonical `git+https` repository URL.

## 2.0.5

- Added npm and GitHub README distribution guidance for install verification, uninstall paths, and local data inspection.
- Added a release checklist with concrete syntax, self-test, hook assertion, scoring fixture, artifact eval, and npm pack dry-run commands.
- Added npm/GitHub-focused package metadata in `skill-fog.metadata.json`.
- Updated the npm package `files` whitelist so published tarballs include runtime files referenced by `SKILL.md` and README plus the validation assets required by the release checklist.
