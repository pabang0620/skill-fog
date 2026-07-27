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
 ░    ███████╗ ██████╗   ██████╗                    ░
 ░    ██╔════╝██╔═══██╗ ██╔════╝                    ░
 ░    █████╗  ██║   ██║ ██║  ███╗                   ░
 ░    ██╔══╝  ██║   ██║ ██║   ██║                   ░
 ░    ██║     ╚██████╔╝ ╚██████╔╝                   ░
 ░    ╚═╝      ╚═════╝   ╚═════╝                    ░
 ░                                                   ░
 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
</pre>
</p>

<h2 align="center">Claude Code watches your patterns. Then builds your tools.</h2>

---

## What it does

Remember the first time you realized you'd been copy-pasting the same prompt for the third week in a row?

You thought: *"I should turn this into a skill."*

You didn't. You typed it again the next day, and the day after that. The intention was there - the action never followed.

**skill-fog closes that gap.** It watches what you ask Claude Code to do across sessions, counts the repetitions, and once the same request pattern has repeated enough, it proposes generating a skill, command, or agent for it - automatically, at the start of your next session. Accept the recommendation and skill-fog writes the file for you.

---

## Install (recommended): Claude Code plugin

```
/plugin marketplace add pabang0620/skill-fog
/plugin install skill-fog
```

That's it. Hooks activate automatically - no `~/.claude/settings.json` or `~/.claude/CLAUDE.md` changes needed. Claude Code discovers `.claude-plugin/plugin.json` and `hooks/hooks.json` and wires up the Stop and SessionStart hooks for you.

For local development (testing a checkout before publishing to the marketplace):

```bash
claude --plugin-dir /path/to/skill-fog
```

**Note:** the plugin path does not install the standalone `skill-fog` CLI (`status` / `review` / `doctor` / `clean`). If you want that, use the npm path below instead (or in addition - see [Using both install paths](#using-both-install-paths-not-recommended)).

## Alternative install: npm / installer script

```bash
npm install -g skill-fog
```

`postinstall` runs `install.sh` for you, which registers the Stop and SessionStart hooks directly in `~/.claude/settings.json` and installs the skill under `~/.claude/skills/skill-fog/`.

This path also gives you the standalone `skill-fog` CLI, which the plugin path does not provide:

```bash
skill-fog status    # show all tracked patterns and their counts
skill-fog review    # browse pending patterns and decide what to build
skill-fog list      # see everything skill-fog has generated for you
skill-fog clean     # remove old, rejected, or stale patterns
skill-fog doctor    # diagnose installation and hook registration
```

Prefer running the installer script directly from a checkout instead of npm:

```bash
git clone https://github.com/pabang0620/skill-fog.git
cd skill-fog
bash install.sh
```

This is not a legacy or deprecated path - it is the only way to get the CLI. Use it if you want `skill-fog doctor`, `skill-fog status`, or scriptable diagnostics; use the plugin path if you just want the hooks with zero setup.

---

## How it works

```
   Every assistant turn ends            Session starts (startup / resume)
            │                                        │
            ▼                                        ▼
     ┌──────────────┐                     ┌───────────────────────┐
     │  Stop hook   │                     │  SessionStart hook    │
     │  (stop.sh)   │                     │  (session-start.sh)   │
     └──────┬───────┘                     └───────────┬───────────┘
            │                                          │
            ▼                                          ▼
  Read new transcript lines                 pending/ has files?
  since last cursor position                          │
            │                                    yes ─┤
            ▼                                          ▼
  Normalize + hash each                    Sort by count (desc),
  user message -> pattern ID               take top 5, inject into
            │                              context, mark snoozed
       ┌────┴──────┐                                  │
       │           │                                  ▼
     < 3x       >= 3x                     [skill-fog] You have N
     2+ sessions                          repeated pattern(s)
       │           │                      pending review.
     keep      write to                              │
    tracking   pending/                               ▼
                                          STEP A: propose + user picks
                                                       │
                                        ┌──────────────┼──────────────┐
                                        ▼              ▼              ▼
                                     skill         command          agent
                                        │              │              │
                                        └──────────────┴──────────────┘
                                                       │
                                                       ▼
                                              ~/.claude/ (done.)
```

1. **Detect** - the Stop hook fires at the end of *every assistant turn* (not at session end). It incrementally parses new lines from the transcript since the last cursor position, masks secrets, normalizes each new user message (strips filenames, UUIDs, URLs, numbers), and hashes it into a pattern ID stored in `~/.skill-fog/patterns.json`.
2. **Promote** - once a pattern's normalized text has appeared **3 or more times across 2 or more sessions**, it is written to `~/.skill-fog/pending/` as a candidate.
3. **Propose** - at the start of your *next* session (`startup` or `resume`, not mid-session `/clear` or `/compact`), the SessionStart hook reads `pending/`, sorts by repeat count descending, takes the top 5, and injects them directly into Claude's context before you type anything. The proposed patterns are immediately marked `snoozed` so they are not re-proposed if ignored.
4. **Generate** - Claude runs STEP A through STEP F: propose a recommended type (skill / command / agent) for each pattern, scan for similar existing artifacts, show a preview, and on confirmation write the file under `~/.claude/` and run the matching quality evaluator (`skill-evaluator` for skills, `agent-evaluator-v2` for commands and agents).

You can also trigger the review flow manually at any time with `/skill-fog` inside Claude Code, which lists active and snoozed patterns for you to pick from.

---

## Uninstall

**Plugin install:**

```
/plugin uninstall skill-fog
```

**npm install:**

```bash
npm uninstall -g skill-fog
```

`preuninstall` automatically runs `uninstall.sh --keep-data --yes`, which removes the registered hooks, the installed skill, and the bundled evaluator agents, while preserving `~/.skill-fog` (your pattern data). Removed files are backed up to `~/.claude/.skill-fog-uninstall-backup.<timestamp>/` before deletion.

To also delete your local pattern data:

```bash
bash uninstall.sh --remove-data
```

`--keep-data` and `--remove-data` are mutually exclusive; running `uninstall.sh` interactively (no flags) prompts you to choose.

---

## Requirements

- `bash`
- `python3` (required - used for transcript parsing, JSON state writes, and secret masking)
- `jq` (optional - used when available for faster JSON queries; skill-fog falls back to `python3` automatically if `jq` is missing)
- Windows: use WSL. skill-fog is a bash-first tool and does not run natively on Windows.

---

## Using both install paths (not recommended)

Installing via both the plugin and npm at the same time registers the hooks twice - once through `hooks/hooks.json` (plugin discovery) and once through entries written into `~/.claude/settings.json` (npm's `install.sh`). This is safe: hook state lives in `~/.skill-fog/` and is cursor-based, so a duplicate Stop/SessionStart invocation is effectively a no-op (it finds nothing new to process). It is still not recommended - pick one install path to keep your setup simple to reason about and uninstall cleanly.

---

## Configuration

skill-fog has no config file today. Behavior is fixed:

- Threshold: 3+ repeats across 2+ sessions before a pattern is promoted to pending.
- Proposals are capped at 5 per session-start injection.
- Cleanup runs automatically every 10 Stop-hook invocations: `rejected` patterns are always removed, and any pattern not seen in the last 30 days is removed regardless of status.

See the [Roadmap](#roadmap) for configurable thresholds as a planned feature.

## Diagnostics (npm install only)

```bash
skill-fog doctor
skill-fog doctor --self-test
```

`doctor` reports each check as `ok`, `warning`, or `failure` - covering JSON tooling, `~/.skill-fog/`, the Stop and SessionStart hook scripts, the installed skill files, and hook registration in Claude settings. `doctor --self-test` runs an isolated install/uninstall cycle in a temporary `HOME` and exits `0` with `0 failures` when the checkout installs and uninstalls cleanly.

See [docs/troubleshooting.md](docs/troubleshooting.md) for recovery steps for specific `doctor` warnings and failures, and for the full uninstall flag reference.

## Local data inspection

skill-fog stores pattern data only under `~/.skill-fog/`. Nothing is sent anywhere.

```bash
ls -la ~/.skill-fog
python3 -m json.tool ~/.skill-fog/patterns.json
ls -la ~/.skill-fog/pending
tail -n 100 ~/.skill-fog/logs/*.log 2>/dev/null || true
```

## Privacy

- API keys, tokens, database URLs, emails, and other common secret patterns are masked at collection time, before anything is written to disk.
- All data stays local under `~/.skill-fog/` - skill-fog does not call any network service.
- Inspect stored data at any time with the commands above, or clean stale entries with `skill-fog clean` (npm install) / by deleting files under `~/.skill-fog/` directly.
- During uninstall, you choose whether to keep or remove `~/.skill-fog/`.

## FAQ

**Why didn't my pattern get proposed?**
Check that it has repeated at least 3 times across at least 2 different Claude Code sessions, that the message isn't shorter than 10 characters after secret masking (before normalization), and that it isn't already `snoozed` or `rejected`. Run `skill-fog status` (npm install) or inspect `~/.skill-fog/patterns.json` directly to see current counts.

**Why does the proposal only show up next session, not immediately?**
Detection happens continuously (every assistant turn), but proposals are only injected at session start, by design - this keeps mid-task context free of interruptions.

**Can I recover a proposal I ignored?**
Yes. Ignored proposals are moved to `snoozed`, not deleted. Run `/skill-fog` inside Claude Code to see and act on snoozed patterns anytime - the `skill-fog review` CLI command only walks pending files awaiting first proposal, so once a pattern is snoozed it no longer shows up there.

---

## How it fits in the ecosystem

There are already great tools in this space - use whichever fits your workflow.

**[ECC (Everything Claude Code)](https://github.com/affaan-m/ECC)** - a full suite of Claude Code extensions including `continuous-learning-v2`, which also collects session patterns via a Stop hook and can promote them into skills with `/evolve`. If you want a comprehensive toolkit, ECC is excellent.

**[Hermes](https://github.com/NousResearch/hermes-agent)** - an agent framework that wraps Claude Code as a sub-agent. Great if you want a higher-level orchestration layer.

**[OpenClaw](https://github.com/claw-orchestrator/openclaw)** - life automation (WhatsApp, calendar, smart home). Different category entirely, but worth knowing about.

skill-fog does one thing: watches which requests you repeat, and when a pattern crosses the threshold, proposes a tool for it automatically - no commands to remember, no manual triggers. If that specific behavior is what you want, skill-fog is for you. If you want a broader suite, go with ECC.

---

## Roadmap

- [x] Stop hook pattern collection
- [x] Threshold-based pending promotion (3x / 2 sessions)
- [x] Skill / command / agent generation
- [x] CLI (`status`, `review`, `list`, `clean`, `doctor`)
- [x] SessionStart hook - deterministic auto-proposal at session start (2.1.0)
- [x] System noise filtering - Claude Code internal messages excluded (2.2.0)
- [x] Smart type recommendation with auto-accept (2.2.0)
- [x] Bundled evaluators - skill-evaluator + agent-evaluator-v2 (2.2.0)
- [x] Propose-once snooze - ignored proposals never repeat (2.3.1)
- [x] Internationalization - English by default, mirrors the user's language (2.4.0)
- [x] Claude Code plugin distribution - `.claude-plugin/` marketplace + manifest (2.5.0)
- [ ] Interactive review TUI (`skill-fog review --interactive`)
- [ ] Pattern similarity clustering (catch near-duplicates)
- [ ] Team export/import (`skill-fog export --team`)
- [ ] VS Code extension
- [ ] Configurable thresholds per project

---

## Contributing

PRs and issues are welcome. This is a bash-first project - keep it simple.

1. Fork: [github.com/pabang0620/skill-fog](https://github.com/pabang0620/skill-fog)
2. Branch: `git checkout -b feature/my-feature`
3. Commit: `git commit -m 'feat: add my feature'`
4. Push: `git push origin feature/my-feature`
5. Open a Pull Request

If you have a pattern that skill-fog should detect better, open an issue with a real example. The normalization logic lives in `hooks/stop.sh` and is easy to extend.

---

## Release Validation Assets

The published package includes the release validation assets listed in `package.json`, including the release checklist, hook benchmark script, eval scripts, and fixtures. To inspect the published tarball:

```bash
npm pack skill-fog --dry-run --json
```

---

## License

MIT (c) [pabang0620](https://github.com/pabang0620)

---

<p align="center">
  <sub>Built for Claude Code users who know they should automate things but never get around to it.</sub>
</p>
