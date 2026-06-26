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

## The fog clears when you stop repeating yourself.

Remember the first time you realized you'd been copy-pasting the same prompt for the third week in a row?

You thought: *"I should turn this into a skill."*

You didn't.

You typed it again the next day. And the day after that. The intention was there — the action never followed.

**skill-fog closes that gap.** It watches what you ask Claude to do, counts the repetitions, and when you've typed the same thing enough times, it tells you — automatically, at the start of your next session — *"Want me to build a tool for this?"* Then it actually builds it.

---

## What's new in v2.2

**Smart type recommendation + bundled evaluators + noise filtering.**

### Auto-recommend skill / command / agent

Previously you had to choose the type yourself, which was confusing. v2.2 analyzes each pattern and recommends the most appropriate type with a one-line reason. Press Enter to accept all recommendations at once — or override per item.

```
[skill-fog] 반복 패턴 3개를 자동화할 수 있어요.

1. "계속진행해줘 실수로 취소했어" (3회/3세션) → 추천: command (재개 트리거)
2. "서버에 반영해야할 파일 뭐 더라?" (3회/2세션) → 추천: command (현재 상태 조회)
3. "일단 사업의 전반적인 이해를..." (3회/3세션) → 추천: command (컨텍스트 파악)

추천대로 진행할까요? (엔터 또는 "자동")
개별 변경: "1 스킬, 3 안함" 처럼 입력
```

### Bundled quality evaluators

Generated artifacts are immediately evaluated by the right agent:

- **Skill** → `skill-evaluator` (SKILL.md 전용 10개 차원 평가)
- **Command / Agent** → `agent-evaluator-v2` (9관점 100점 평가)

Both agents are included in the package and installed automatically. No separate setup needed.

### System noise filtering

Claude Code generates many internal messages that look like user patterns but aren't — `[request interrupted by user]`, `<local-command-stdout>`, `this session is being continued`, etc. v2.2 filters these at collection time so they never appear as suggestions.

---

## What's new in v2.3

**Propose once, never repeat.**

Previously, if you ignored a suggestion and kept working, the same pattern would appear again at the start of the next session — and the one after that, indefinitely.

v2.3 fixes this: once a pattern is proposed, it's immediately moved to `snoozed` state. If you ignore it, it won't come up again automatically. When you're ready to act on it, use `/skill-fog` to pull up the full list including snoozed patterns and pick what to build.

| Behavior | Before v2.3 | v2.3+ |
|---|---|---|
| Ignore the proposal | Asked again next session | Not asked again |
| Explicitly skip ("나중에") | Re-queued for next session | Stays snoozed |
| Explicitly reject ("거부") | Marked rejected, never again | Same |
| Want to revisit later | — | `/skill-fog` shows snoozed patterns |

---

## What's new in v2.4

**Speaks your language.**

Previously all proposals were hardcoded in Korean. v2.4 makes every user-facing message English by default and instructs Claude to **respond in the same language you're using** — so if you chat in English you get English proposals, and Korean users still get Korean. Korean input words like `나중에` (later) and `거부` (reject) are still recognized.

```
[skill-fog] You have 3 repeated pattern(s) pending review.

1. "deploy the frontend build to staging" — 4x, 3 sessions → recommended: command (resume trigger)
2. "summarize the overall scope of the project" — 3x, 2 sessions → recommended: command (context lookup)
3. "find every place that calls the old API" — 3x, 3 sessions → recommended: agent (needs analysis)

Proceed with the recommendations? (Enter or "auto")
```

---

## What's new in v2.1.0

**Session-start auto-proposal via hook.**

Previously, skill-fog asked Claude to remind you about pending patterns every few messages — which meant Claude sometimes forgot, got distracted, or skipped it entirely. It was LLM-dependent and unreliable.

v2.1.0 replaces that with a `SessionStart` hook. The moment Claude Code opens a new session, a shell script fires and injects any pending patterns directly into Claude's context — before you type your first message. Claude sees them. Claude always proposes them. No prompting required.

---

## How it works

```
  Session ends                Session starts
       │                            │
       ▼                            ▼
  ┌──────────────┐         ┌──────────────────────┐
  │  Stop Hook   │         │  SessionStart Hook    │
  │  (stop.sh)   │         │  (session-start.sh)   │
  └──────┬───────┘         └──────────┬────────────┘
         │                            │
         ▼                            ▼
  ┌──────────────────┐      pending/ exists?
  │ Normalize + Hash │           │
  │ "fix line 23"    │      Yes ─┤
  │  → pattern ID    │           ▼
  └──────┬───────────┘    ┌──────────────────────┐
         │                │ Inject into context  │
    ┌────┴──────┐         │ before first message │
    │           │         └──────────┬───────────┘
  < 3x      >= 3x                   │
    │       2+ sessions             ▼
  Keep      ┌──────────┐    [skill-fog] 검토 대기 중인
 watching   │ pending/ │    반복 패턴 N개가 있습니다.
            └────┬─────┘           │
                 │                  ▼
                 └──────► STEP A: 제안 + 사용자 선택
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

```bash
skill-fog doctor
skill-fog doctor --self-test
```

Expected result:

- `skill-fog doctor` exits successfully and reports the installed files, Stop hook, SessionStart hook, and local data directory status.
- `skill-fog doctor --self-test` exits with code `0`, reports `0 failures`, and removes its temporary directory when it exits.

---

## How it grows you

### Step 1 — Detect

Every time your Claude Code session ends, a Stop hook silently reads your message history. It normalizes the text (strips filenames, numbers, specifics) and hashes the pattern. No data leaves your machine.

### Step 2 — Propose (automatically)

When the same normalized pattern appears **3+ times across 2+ sessions**, skill-fog saves it as a pending suggestion in `~/.skill-fog/pending/`.

At the **start of your next session**, a SessionStart hook fires before you type anything. Pending patterns are injected into Claude's context. Claude sees them and immediately asks what you want to do — no commands needed.

After proposing, skill-fog immediately marks the patterns as **snoozed** and removes the pending files. If you ignore the proposal and continue working, you won't be asked again next session. Use `/skill-fog` to revisit snoozed patterns whenever you're ready.

### Step 3 — Generate

skill-fog recommends the most appropriate type (skill / command / agent) for each pattern. Press Enter to accept all recommendations, or override per item. After approval, skill-fog writes the file into `~/.claude/` and immediately runs the matching quality evaluator — `skill-evaluator` for skills, `agent-evaluator-v2` for commands and agents. The pattern is then marked as accepted.

---

## Auto-Proposal Reliability

| Trigger method | Reliability | Notes |
|---|---|---|
| SessionStart hook (v2.1.0+) | **Deterministic** | Shell runs before first message; Claude always sees it |
| LLM instruction (≤v2.0.x) | ~60–70% | Claude could forget, skip, or deprioritize |

The hook approach fires via Claude Code's native hook system (`~/.claude/settings.json`). It doesn't depend on Claude's attention or memory — it works the same way every time.

---

## CLI Commands

| Command | Description |
|---|---|
| `skill-fog status` | Show all tracked patterns and their counts |
| `skill-fog review` | Browse pending patterns and decide what to build |
| `skill-fog list` | See everything skill-fog has generated for you |
| `skill-fog clean` | Remove old, rejected, or stale patterns |
| `skill-fog doctor` | Diagnose installation and hook registration |
| `skill-fog doctor --self-test` | Run isolated install/uninstall checks in a temporary HOME |

You can also trigger the review flow any time with `/skill-fog` inside Claude Code.

---

## Diagnostics

```bash
skill-fog doctor
```

`doctor` reports each check with one of these statuses:

- `ok` — dependency, file, directory, or hook is present and usable.
- `warning` — skill-fog can usually continue, but setup is incomplete (e.g. missing `jq` while `python3` is available).
- `failure` — a required piece is missing: `~/.skill-fog/`, Stop hook script, SessionStart hook script, `SKILL.md`, or hook registration in Claude settings.

For install validation:

```bash
skill-fog doctor --self-test
```

The self-test creates a temporary HOME, runs `install.sh`, verifies both Stop and SessionStart hooks are registered and executable, runs `doctor` (expects `0 failures`), reinstalls (expects no duplicate hooks), then runs `uninstall.sh` twice and verifies all hooks and skill files are removed cleanly.

See [docs/troubleshooting.md](docs/troubleshooting.md) for recovery steps and uninstall behavior.

---

## Uninstall

```bash
# If installed via npm
npm uninstall -g skill-fog

# Remove hooks/skills from a checkout
bash uninstall.sh
```

Non-interactive flags:

- `--yes` — answer yes to all prompts
- `--keep-data` — preserve `~/.skill-fog` without prompting
- `--remove-data` — remove `~/.skill-fog` without prompting

---

## Local Data Inspection

skill-fog stores pattern data only under `~/.skill-fog/`. Nothing is sent anywhere.

```bash
ls -la ~/.skill-fog
find ~/.skill-fog -maxdepth 2 -type f -print
python3 -m json.tool ~/.skill-fog/patterns.json
ls -la ~/.skill-fog/pending
tail -n 100 ~/.skill-fog/logs/*.log 2>/dev/null || true
```

Remove stale rejected patterns and old logs:

```bash
skill-fog clean
```

---

## How it fits in the ecosystem

There are already great tools in this space — use whichever fits your workflow.

**[ECC (Everything Claude Code)](https://github.com/affaan-m/ECC)** — 210K+ stars, a full suite of Claude Code extensions including `continuous-learning-v2`, which also collects session patterns via a Stop hook and can promote them into skills with `/evolve`. If you want a comprehensive toolkit, ECC is excellent.

**[Hermes](https://github.com/NousResearch/hermes-agent)** — an agent framework that wraps Claude Code as a sub-agent. Great if you want a higher-level orchestration layer.

**[OpenClaw](https://github.com/claw-orchestrator/openclaw)** — life automation (WhatsApp, calendar, smart home). Different category entirely, but worth knowing about.

---

skill-fog does one thing: **watches which requests you repeat, and when a pattern crosses the threshold, proposes a tool for it automatically** — no commands to remember, no manual triggers. If that specific behavior is what you want, skill-fog is for you. If you want a broader suite, go with ECC.

---

## Privacy

All pattern data lives in `~/.skill-fog/` on your machine. Nothing is sent anywhere.

- API keys, tokens, emails, and secrets are masked automatically before storage
- Inspect files directly with the commands in [Local Data Inspection](#local-data-inspection)
- Delete stale entries with `skill-fog clean`
- During uninstall, choose whether to keep or remove `~/.skill-fog/`

---

## Roadmap

- [x] Stop hook pattern collection
- [x] Threshold-based pending promotion (3x / 2 sessions)
- [x] Skill / command / agent generation
- [x] CLI (`status`, `review`, `list`, `clean`, `doctor`)
- [x] **SessionStart hook — deterministic auto-proposal at session start (v2.1.0)**
- [x] **System noise filtering — Claude Code internal messages excluded (v2.2.0)**
- [x] **Smart type recommendation with auto-accept (v2.2.0)**
- [x] **Bundled evaluators — skill-evaluator + agent-evaluator-v2 (v2.2.0)**
- [x] **Propose-once snooze — ignored proposals never repeat (v2.3.1)**
- [x] **Internationalization — English by default, mirrors the user's language (v2.4.0)**
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

## Release Validation Assets

The published package includes the release validation assets listed in `package.json`, including the release checklist, hook benchmark script, eval scripts, and fixtures. To inspect the published tarball:

```bash
npm pack skill-fog --dry-run --json
```

---

## License

MIT © [pabang0620](https://github.com/pabang0620)

---

<p align="center">
  <sub>Built for Claude Code users who know they should automate things but never get around to it.</sub>
</p>
