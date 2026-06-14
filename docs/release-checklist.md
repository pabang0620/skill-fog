# Release Checklist

Use this checklist before publishing `skill-fog` to npm or updating the GitHub release/README. Run commands from the repository root.

## Scope

- Primary distribution targets: npm package and GitHub README.
- Do not claim support for unverified skill marketplaces.
- Do not edit runtime scripts, benchmark scripts, fixtures, references, or plans as part of checklist execution.

## Required Checks

### 1. JSON Syntax

```bash
python3 -m json.tool package.json >/dev/null
python3 -m json.tool skill-fog.metadata.json >/dev/null
```

Pass criteria: both commands exit with code `0` and print no errors.

### 2. Shell Syntax

```bash
bash -n install.sh
bash -n uninstall.sh
bash -n hooks/stop.sh
bash -n scripts/bench-hook.sh
bash -n scripts/run-evals.sh
```

Pass criteria: every command exits with code `0`.

### 3. Python Syntax

```bash
python3 -m py_compile scripts/score-patterns.py scripts/eval-artifacts.py
```

Pass criteria: command exits with code `0`.

### 4. Doctor Self-Test

```bash
./bin/skill-fog doctor --self-test
```

Pass criteria: command exits with code `0`, reports an isolated temporary HOME self-test, verifies the installed PATH `skill-fog doctor --self-test` layout probe can find its runtime bundle under `~/.skill-fog/`, verifies every `references/*.md` file linked from the installed `~/.claude/skills/skill-fog/SKILL.md` exists under `~/.claude/skills/skill-fog/references/`, reports `0 failures` for the install doctor check inside that self-test, proves reinstall does not duplicate the Stop hook, proves uninstall is idempotent, and cleans up the temporary HOME.

### 5. Hook Assertions

```bash
scripts/bench-hook.sh --assert-only
```

Pass criteria: command exits with code `0`. The assertion fixtures must create exactly one pending pattern at count `3` across `2` sessions for Claude JSONL v1 and v2, and the Cursor regression fixture must not increment pattern counts on the second run.

### 6. Hook JSON Budget

```bash
scripts/bench-hook.sh --benchmark-only --runs 5 --warmups 1 --json --fail-p95-ms 10000
```

Pass criteria: command exits with code `0`; JSON output is valid; every result status is `ok` or `warn`; no result is `performance_budget_exceeded`; each measured p95 is less than or equal to `10000` ms.

### 7. Scoring Fixtures

```bash
python3 scripts/score-patterns.py --fixture fixtures/patterns/ranking-basic.json
python3 scripts/score-patterns.py --fixture fixtures/patterns/privacy-risk.json
```

Pass criteria: both commands exit with code `0`; each JSON payload has `"ok": true` and an empty `"failures"` array; privacy-risk output must not contain the raw forbidden secret values from the fixture.

### 8. Artifact Evals

```bash
scripts/run-evals.sh --all
```

Pass criteria: command exits with code `0`; JSON output has `"ok": true`; every case has `result` equal to `expected_result`; simulated drafts are written only under the runner temporary directory.

### 9. npm Pack Dry-Run

```bash
npm pack --dry-run --json
```

Pass criteria: command exits with code `0`; output is valid JSON; the file list includes runtime files referenced by `SKILL.md` and README, including `SKILL.md`, `bin/skill-fog`, `hooks/stop.sh`, `install.sh`, `uninstall.sh`, `postinstall.js`, `references/*.md`, `docs/troubleshooting.md`, `docs/release-checklist.md`, `CHANGELOG.md`, `README.md`, `package.json`, and `skill-fog.metadata.json`. The file list must not include `.git`, plans, `scripts/__pycache__`, or unrelated local artifacts.

## Publish Notes

1. Confirm `package.json.version`, `SKILL.md` frontmatter version, and `skill-fog.metadata.json.version` match.
2. Confirm the GitHub README matches the npm README in the packed tarball.
3. Publish with npm only after all required checks pass.

## Self-Defined Metadata

`skill-fog.metadata.json` is a project-owned npm/GitHub distribution metadata file. It is not a marketplace manifest and does not claim compatibility with skills.sh, GitHub skill registries, or any unsupported host.

Required fields:

- `$schema`: URL pointing to this self-defined schema documentation.
- `schema_version`: version of this metadata schema.
- `schema_description`: plain-language statement that the file is self-defined.
- `name`: npm package name.
- `version`: package version, matching `package.json` and `SKILL.md`.
- `license`: package license.
- `repository`: canonical GitHub repository URL.
- `install_command`: primary npm install command.
- `privacy_note`: local-data/privacy statement.
- `supported_host`: verified host name.
- `distribution_targets`: supported distribution surfaces.
