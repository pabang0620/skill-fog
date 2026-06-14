# Troubleshooting

Use this page when `skill-fog doctor` reports a warning or failure, or when you need a non-interactive uninstall.

## `skill-fog doctor` statuses

`skill-fog doctor` checks the local install under the current `HOME` and prints a summary like:

```text
Summary: 7 ok  2 warnings  0 failures
```

Status meanings:

- `ok`: the checked item is present and usable.
- `warning`: skill-fog can usually keep working, but the setup is incomplete or using a fallback.
- `failure`: a required install item is missing or unusable and should be fixed before relying on skill-fog.

Current checks include JSON tooling, `~/.skill-fog/`, `~/.skill-fog/pending/`, `~/.skill-fog/patterns.json`, the Stop hook script, the installed `SKILL.md`, Claude settings hook registration, and whether `skill-fog` is available in `PATH`.

Common warnings:

- `jq installed` warning: `jq` is missing, so skill-fog uses the `python3` fallback when available.
- `python3 available` warning: `python3` is missing. Install `python3` if `jq` is also unavailable.
- `~/.skill-fog/patterns.json` warning: the file has not been created yet. It is created after skill-fog records patterns.
- `settings.json exists` warning: Claude settings do not exist yet. Re-run `install.sh` after Claude Code has created settings, or let the installer create them.
- `skill-fog in PATH` warning: add `~/.local/bin` to `PATH`, or run the CLI through its full path.

Common failures:

- `~/.skill-fog/ directory` failure: re-run `install.sh`.
- `~/.skill-fog/pending/ directory` failure: re-run `install.sh`.
- `stop.sh hook` failure: re-run `install.sh`.
- `stop.sh hook (executable)` failure: run `chmod +x ~/.skill-fog/hooks/stop.sh`.
- `SKILL.md installed` failure: re-run `install.sh`.
- `Stop hook registered in settings.json` failure: re-run `install.sh` so Claude Code can call the Stop hook.

## Self-test install validation

Run:

```bash
skill-fog doctor --self-test
```

The self-test uses a temporary HOME instead of your real HOME. It copies the current checkout's `install.sh`, `uninstall.sh`, `SKILL.md`, `bin/skill-fog`, `hooks/stop.sh`, and `package.json` when present into a temporary repo, then runs the install and uninstall flows there.

It validates that:

- `install.sh` can create `~/.skill-fog`, `~/.skill-fog/pending`, `~/.skill-fog/patterns.json`, and the Stop hook script in a clean HOME.
- The installed Stop hook script is executable.
- `SKILL.md` is installed under `~/.claude/skills/skill-fog/SKILL.md`.
- `~/.claude/settings.json` is created with a skill-fog Stop hook entry.
- `~/.local/bin/skill-fog` is created.
- `skill-fog doctor` reports `0 failures` in that temporary HOME.
- Running `install.sh` a second time leaves exactly one skill-fog Stop hook registration.
- Running `uninstall.sh` twice with data preservation removes the installed skill directory, the CLI link, and the Stop hook registration while leaving `~/.skill-fog` in place.

This proves the checkout can install cleanly, that reinstalling does not duplicate the Stop hook, and that repeated data-preserving uninstall removes installed integration points without deleting stored skill-fog data. It does not prove that your real HOME is configured correctly, that Claude Code will run a future session, or that generated skills, commands, or agents are correct.

The temporary HOME is deleted when the self-test exits.

## Uninstall flags

Run the uninstaller from a skill-fog checkout:

```bash
bash uninstall.sh
```

For non-interactive use:

- `--yes`: answer yes to confirmation prompts.
- `--keep-data`: keep `~/.skill-fog` without prompting.
- `--remove-data`: delete `~/.skill-fog` without prompting.

`--keep-data` and `--remove-data` are mutually exclusive. Using both exits with an error.

Examples:

```bash
bash uninstall.sh --yes --keep-data
bash uninstall.sh --yes --remove-data
```

The uninstaller removes the Claude Stop hook, the installed `~/.claude/skills/skill-fog` directory, skill-fog's Claude instruction entry, and skill-fog-owned CLI symlinks.

CLI removal is conservative. If `~/.local/bin/skill-fog` or `~/bin/skill-fog` is a symlink that points to a skill-fog CLI, the uninstaller removes it. If either path is a regular file named `skill-fog`, the uninstaller skips it and prints a warning instead of deleting it.
