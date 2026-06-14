<!-- Badges -->
<p align="center">
  <img src="https://img.shields.io/npm/v/skill-fog?color=blueviolet&style=flat-square" alt="npm version" />
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="license" />
  <img src="https://img.shields.io/badge/Claude%20Code-compatible-orange?style=flat-square&logo=anthropic" alt="claude-code compatible" />
</p>

<!-- Logo / Title -->
<p align="center">
<pre>
 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
 ░                                                   ░
 ░    ███████╗██╗  ██╗██╗██╗     ██╗                ░
 ░    ██╔════╝██║ ██╔╝██║██║     ██║                ░
 ░    ███████╗█████╔╝ ██║██║     ██║                ░
 ░    ╚════██║██╔═██╗ ██║██║     ██║                ░
 ░    ███████║██║  ██╗██║███████╗███████╗           ░
 ░    ╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝           ░
 ░                                                   ░
 ░         F  O  G                                   ░
 ░                                                   ░
 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
</pre>
</p>

<h2 align="center">Claude Code watches your patterns. Then builds your tools.</h2>

---

## The fog clears when you stop repeating yourself.

Remember the first time you realized you'd been copy-pasting the same prompt for the third week in a row?

You thought: *"I should turn this into a skill."*

You didn't.

You typed it again the next day. And the day after that. The intention was there — the action never followed.

**skill-fog closes that gap.** It watches what you ask Claude to do, counts the repetitions, and when you've typed the same thing enough times, it asks: *"Want me to build a tool for this?"* Then it actually builds it.

---

## How it works

```
  Your Claude Code session
           │
           ▼
  ┌─────────────────┐
  │   Stop Hook     │  ← Fires silently at every session end
  │  (stop.sh)      │
  └────────┬────────┘
           │
           ▼
  ┌─────────────────────────────┐
  │  Normalize + Hash           │
  │  "fix error on line 23"     │  → "fix error on line NUM"
  │  "fix error on line 145"    │  → same pattern ID
  └────────┬────────────────────┘
           │
     ┌─────┴──────┐
     │            │
   < 3x        >= 3x, 2+ sessions
     │            │
  Keep        ┌───▼────────────────┐
 watching     │  pending/{id}.json │
              └───────┬────────────┘
                      │
              Next session start
                      │
                      ▼
      ┌───────────────────────────────┐
      │  "I noticed you've asked me   │
      │   to fix line errors 5 times. │
      │   Want me to build a skill?"  │
      └───────────────────────────────┘
                      │
           ┌──────────┼──────────┐
           ▼          ▼          ▼
        skill      command     agent
           │          │          │
           └──────────┴──────────┘
                      │
                      ▼
             ~/.claude/ (done.)
```

---

## Installation

`skill-fog@2.0.6` is published on npm and is the current `latest` dist-tag.

```bash
# npm (recommended)
npm install -g skill-fog
```

```bash
# curl (no node required)
curl -fsSL https://raw.githubusercontent.com/pabang0620/skill-fog/main/install.sh | bash
```

**Requirements:** `bash >= 4.0`, `jq` (or `python3` as fallback), Claude Code

## Verify Install

Run these checks after installing the published npm package:

```bash
skill-fog doctor
skill-fog doctor --self-test
```

Expected result:

- `skill-fog doctor` exits successfully and reports the installed files, Stop hook, and local data directory status.
- `skill-fog doctor --self-test` exits with code `0`, reports `0 failures` inside its isolated temporary HOME, and removes its temporary directory when it exits.

## Release Validation Assets

The published package includes the release validation assets listed in `package.json`, including the release checklist, hook benchmark script, eval scripts, and fixtures. To inspect the published tarball contents without installing:

```bash
npm pack skill-fog --dry-run --json
```

To inspect a local checkout before a future publish:

```bash
npm pack --dry-run --json
```

---

## How it grows you

### Step 1 — Detect

Every time your Claude Code session ends, a Stop hook silently reads your message history. It normalizes the text (strips filenames, numbers, specifics) and hashes the pattern. No data leaves your machine.

### Step 2 — Propose

When the same normalized pattern appears **3+ times across 2+ sessions**, skill-fog promotes it to `pending`. The next time you open Claude Code, it surfaces the suggestion naturally — no interruptions, no popups.

### Step 3 — Generate

Say yes. skill-fog writes the actual `SKILL.md`, slash command, or agent definition into `~/.claude/` — ready to use in your next session.

---

## CLI Commands

| Command | Description |
|---|---|
| `skill-fog status` | Show all tracked patterns and their counts |
| `skill-fog review` | Browse pending patterns and decide what to build |
| `skill-fog list` | See everything skill-fog has generated for you |
| `skill-fog clean` | Remove old, rejected, or stale patterns |
| `skill-fog doctor` | Diagnose installation and hook registration |
| `skill-fog doctor --self-test` | Run isolated install and uninstall checks in a temporary HOME |

---

## Diagnostics

Run:

```bash
skill-fog doctor
```

`doctor` reports each check with one of these statuses:

- `ok` means the checked dependency, file, directory, hook, or PATH entry is present and usable.
- `warning` means skill-fog can usually continue, but the setup is incomplete or using a fallback, such as missing `jq` while `python3` is available.
- `failure` means a required install piece is missing or unusable, such as `~/.skill-fog/`, the Stop hook script, `SKILL.md`, or the Stop hook entry in Claude settings.

For install validation, run:

```bash
skill-fog doctor --self-test
```

The self-test creates a temporary HOME, copies the local skill-fog files into it, runs `install.sh`, runs `skill-fog doctor`, then runs `install.sh` again. It proves the current checkout can install into a clean HOME, produce a doctor report with `0 failures`, and avoid duplicate Stop hook registration on reinstall. It then runs `uninstall.sh` twice with data preservation and verifies the installed skill directory, CLI link, and Stop hook registration are removed while `~/.skill-fog` remains. It deletes the temporary HOME when it exits.

See [docs/troubleshooting.md](docs/troubleshooting.md) for recovery steps and uninstall behavior.

---

## Uninstall

If installed through npm, remove the global package:

```bash
npm uninstall -g skill-fog
```

To remove Claude Code hook/skill files from a checkout or unpacked npm package, run:

```bash
bash uninstall.sh
```

Use non-interactive flags when scripting:

- `--yes` answers yes to confirmation prompts.
- `--keep-data` preserves `~/.skill-fog` without prompting.
- `--remove-data` removes `~/.skill-fog` without prompting.

`--keep-data` and `--remove-data` cannot be used together. During CLI cleanup, the uninstaller removes skill-fog-owned symlinks only. If `~/.local/bin/skill-fog` or `~/bin/skill-fog` is a regular file instead of a symlink, it is skipped.

## Local Data Inspection

skill-fog stores pattern data only under `~/.skill-fog/`. Inspect it with:

```bash
ls -la ~/.skill-fog
find ~/.skill-fog -maxdepth 2 -type f -print
python3 -m json.tool ~/.skill-fog/patterns.json
ls -la ~/.skill-fog/pending
tail -n 100 ~/.skill-fog/logs/*.log 2>/dev/null || true
```

Remove stale rejected patterns and old logs with:

```bash
skill-fog clean
```

Remove all local data during uninstall with:

```bash
bash uninstall.sh --yes --remove-data
```

---

## Why skill-fog?

> *"Hermes remembers. OpenClaw automates. skill-fog evolves."*

| | Hermes | OpenClaw | **skill-fog** |
|---|---|---|---|
| What it does | Persistent memory across sessions | Automated code actions | Detects your patterns, builds your tools |
| Requires server | Yes | Yes | **No — pure bash** |
| Learns from you | No | No | **Yes — gets smarter every session** |
| Output | Context | Actions | **Reusable skills, commands, agents** |
| Runtime | Custom | Custom | **bash + SKILL.md — Claude Code native** |
| Setup complexity | Medium | Medium | **One curl command** |

skill-fog doesn't try to be a memory system or an automation layer. It's a **pattern → tool compiler**. The more you use Claude Code, the more skill-fog learns what deserves to be a permanent tool in your workflow.

---

## Privacy

All pattern data lives in `~/.skill-fog/` on your machine. Nothing is sent anywhere.

- API keys, tokens, emails, and secrets are masked automatically before storage
- You can inspect files directly with the commands in [Local Data Inspection](#local-data-inspection)
- You can delete stale local entries with `skill-fog clean`
- During uninstall, choose whether to keep or remove `~/.skill-fog/`

---

## Roadmap

- [x] Stop hook pattern collection
- [x] Threshold-based pending promotion (3x / 2 sessions)
- [x] Skill / command / agent generation
- [x] CLI (`status`, `review`, `list`, `clean`, `doctor`)
- [ ] Interactive review TUI (`skill-fog review --interactive`)
- [ ] Pattern similarity clustering (catch near-duplicates)
- [ ] Team export/import (`skill-fog export --team`)
- [ ] VS Code extension
- [ ] Configurable thresholds per project

---

## Contributing

PRs and issues are welcome. This is a bash-first project — keep it simple.

1. Fork: [github.com/pabang0620/skill-fog](https://github.com/pabang0620/skill-fog)
2. Branch: `git checkout -b feature/my-feature`
3. Commit: `git commit -m 'feat: add my feature'`
4. Push: `git push origin feature/my-feature`
5. Open a Pull Request

If you have a pattern that skill-fog should detect better, open an issue with a real example. The normalization logic lives in `hooks/stop.sh` and is easy to extend.

---

## License

MIT © [pabang0620](https://github.com/pabang0620)

---

<p align="center">
  <sub>Built for Claude Code users who know they should automate things but never get around to it.</sub>
</p>
