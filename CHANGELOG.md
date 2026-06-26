# Changelog

All notable changes to this package are documented here.

## Unreleased

## 2.4.0

### Changed
- **Internationalization**: all user-facing output is now English by default, and SKILL.md/references instruct Claude to **respond in the same language the user is using**. English users now get English proposals; Korean users still get Korean. Korean input trigger words (`나중에`, `거부`, etc.) remain recognized.
- `SKILL.md`: fully translated to English; added an explicit language-mirroring rule.
- `hooks/session-start.sh`: injected proposal text translated to English with a "respond in the user's language" reminder.
- `references/pattern-scoring.md`, `references/artifact-generation.md`: proposal/preview/completion templates translated to English.
- `install.sh` / `uninstall.sh`: the CLAUDE.md trigger block is now English (marker `# skill-fog: pattern detection`). Install migrates the legacy Korean block; uninstall removes both old and new markers.

### Fixed
- `references/privacy-and-redaction.md`: the "later/skip" section no longer contradicts snooze — it now reflects that a proposed pattern is already `snoozed` and is not re-queued.

## 2.3.1

### Fixed
- **Propose-once snooze**: once a pattern is proposed at session start, it is immediately moved to `snoozed` and its pending file removed, so ignoring a proposal no longer re-asks every session. `stop.sh` excludes `snoozed` from pending re-promotion. Revisit anytime via `/skill-fog`.

## 2.3.0

### Added
- **System noise filtering** (`hooks/stop.sh`): Claude Code internal messages (`[request interrupted]`, `<local-command-stdout>`, `this session is being continued`, etc.) are filtered at collection time.
- **Smart type recommendation**: each pending pattern is classified into a recommended skill/command/agent with a one-line reason; press Enter to accept all.
- **Bundled evaluators**: `skill-evaluator` and `agent-evaluator-v2` are included in the package and installed to `~/.claude/agents/`.

### Fixed
- `uninstall.sh`: now removes the bundled evaluator agents on uninstall.

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
