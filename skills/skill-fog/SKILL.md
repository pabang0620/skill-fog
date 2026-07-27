---
name: skill-fog
description: Detects repeated request patterns and proposes generating a skill, command, or agent. A SessionStart hook injects pending patterns at session start, and it also activates when the user explicitly runs /skill-fog.
version: 2.5.0
triggers:
  - /skill-fog
---

# skill-fog skill

## Role
A helper that detects the user's repeated request patterns and, once a threshold is reached, proposes generating a skill, command, or agent.

## Language rule (IMPORTANT)
Always communicate with the user in the **same language the user is using**. Every template and message in this skill and its references is written in English as a reference — translate the user-facing text into the user's language before showing it. (e.g. if the user writes in Korean, respond in Korean.)

## Activation conditions
- When the **SessionStart hook** injects pending patterns into context at session start → run STEP A.
- When the user explicitly types `/skill-fog` → run STEP A.

## Behavior at session start
The SessionStart hook (`~/.skill-fog/hooks/session-start.sh`) runs automatically at session start (startup/resume).
If pending patterns exist, that information is injected into context and a `[skill-fog] You have N repeated pattern(s) pending review.` message appears.
When you see this message, run STEP A immediately.
Add the pid of each proposed pattern to the in-session `session_proposed` set (prevents double-firing).
`session_proposed` is always reset to an empty set when a new session starts.

## Step routing

### STEP A: Propose pending patterns at session start
Run when pending patterns were injected. Handle pid de-duplication, `patterns.json` status, sort order, and message format per [pattern-scoring.md](references/pattern-scoring.md).

### STEP B: Handle the user's response
- `later` / `skip` / `나중에` / `스킵`: The pattern is already `snoozed`. Do nothing further; just tell the user they can call it up anytime with `/skill-fog`.
- `reject` / `no` / `거부` / `아니오`: Update status to `rejected` and delete the pending file if it still exists.
- `skill` / `command` / `agent`: Proceed to STEP C.

State transitions and file writes are described in [privacy-and-redaction.md](references/privacy-and-redaction.md).

### STEP C: Scan for similar items
Before the choice, check whether it overlaps with existing skill, command, or agent files. Scan paths and the question format when a similar item is found are in [artifact-generation.md](references/artifact-generation.md).

### STEP D: Generate preview and confirm
Before actually creating the file, show a preview for the chosen type. Skill/command/agent templates, the examples-section inclusion rules, and the confirmation question are in [artifact-generation.md](references/artifact-generation.md).

### STEP E: Create the actual file
After user confirmation, create the file. Name-validation rules and per-type path rules are in [artifact-generation.md](references/artifact-generation.md).

### STEP E.5: Automatic quality improvement (optional)
Right after file creation, ask the user once for approval. On approval, call the evaluator agent and apply its suggestions. The approval message, agent invocation, score threshold, and improvement procedure are in [artifact-generation.md](references/artifact-generation.md).

### STEP F: Completion
After creation, update `patterns.json` status to `accepted`, delete the pending file, and print the completion message. The exact update fields and completion message are in [artifact-generation.md](references/artifact-generation.md).

## Manual invocation (/skill-fog)
When the user explicitly types `/skill-fog`:

```bash
cat ~/.skill-fog/patterns.json 2>/dev/null || echo '{"patterns":{}}'
```

The output format, handling of active pattern selection, `session_proposed` updates, and STEP B entry conditions are in [pattern-scoring.md](references/pattern-scoring.md).

## Safety rules
- SKILL.md uses `patterns.json` as read-only. Pattern accumulation (count increment, session additions) is handled only by `stop.sh` at the end of each assistant turn.
- Patterns proposed at session start are moved to `snoozed` state. If ignored, they are not re-proposed in the next session.
- If a pattern's status is `accepted` / `rejected` / `snoozed`, do not create a new pending file.
- `snoozed` patterns can be reviewed and selected for generation via the `/skill-fog` manual invocation list.
- Do not ask again about a pattern already proposed within the same session.
- `rejected` patterns are ignored permanently.
- Follow the generation quality rules in [artifact-generation.md](references/artifact-generation.md).
- Follow [privacy-and-redaction.md](references/privacy-and-redaction.md) for sensitive data, redaction, atomic writes, and local file state transitions.
- Load [troubleshooting.md](references/troubleshooting.md) only when diagnosis is needed.

## Reference Loading
| Situation | Reference to load | Contents |
| --- | --- | --- |
| pending review, threshold checks, manual `/skill-fog` listing | [pattern-scoring.md](references/pattern-scoring.md) | normalization, pid generation, threshold conditions, pending sort, proposal messages |
| scoring/threshold checks | [pattern-scoring.md](references/pattern-scoring.md) | interpreting `THRESHOLD_MET`, `TRACKING`, `NO_DATA` results |
| artifact generation | [artifact-generation.md](references/artifact-generation.md) | similar-item scan, preview templates, name/path rules, completion handling |
| privacy/redaction, status updates, pending writes | [privacy-and-redaction.md](references/privacy-and-redaction.md) | active/rejected/accepted transitions, pending create/delete, atomic JSON writes |
| troubleshooting | [troubleshooting.md](references/troubleshooting.md) | diagnosing missing files, broken JSON, duplicate proposals, pack/install issues |
