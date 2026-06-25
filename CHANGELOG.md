# Changelog

All notable changes to this package are documented here.

## Unreleased

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
