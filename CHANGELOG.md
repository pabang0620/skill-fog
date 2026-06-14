# Changelog

All notable changes to this package are documented here.

## Unreleased

## 2.0.6

- Added push-protection-safe fixture placeholders for release packaging checks.
- Prepared release-readiness harness assets for npm package distribution.
- Fixed npm package metadata by using the canonical `git+https` repository URL.

## 2.0.5

- Added npm and GitHub README distribution guidance for install verification, uninstall paths, and local data inspection.
- Added a release checklist with concrete syntax, self-test, hook assertion, scoring fixture, artifact eval, and npm pack dry-run commands.
- Added npm/GitHub-focused package metadata in `skill-fog.metadata.json`.
- Updated the npm package `files` whitelist so published tarballs include runtime files referenced by `SKILL.md` and README plus the validation assets required by the release checklist.
