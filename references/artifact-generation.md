# Artifact Generation Reference

Load this reference when the user chooses `skill`, `command`, or `agent`.

All user-facing text below is in English as a reference — translate it into the user's language before showing it.

## Similar item scan
Before generating a preview, check whether the requested artifact overlaps with existing files.

```bash
find ~/.claude/skills/ -name "*.md" 2>/dev/null
find ~/.claude/commands/ -name "*.md" 2>/dev/null
find ~/.claude/agents/ -name "*.md" 2>/dev/null
```

If a similar item is found, ask:

```text
This looks similar to the existing `{existing_name}`.
- Merge: add this pattern as an example to the existing file
- Create separately: split into a new file
Which would you like?
```

If no similar item is found, proceed directly to preview generation.

## Preview generation
Show a preview before creating a file.

For skill previews, include sections based on available examples:

- `examples[0]` is always included.
- Add the "Example 2" section only when `examples[1]` exists.
- Add the "Example 3" section only when `examples[2]` exists.

Skill preview:

```markdown
---
name: {auto_generated_name}
description: {description written in the third person}
---

# {skill name}

## Role
{role description based on the observed pattern}

## When to use
{trigger conditions — be explicit}

## How it works
{step-by-step procedure}

## Examples
### Example 1
{examples[0] — use the redacted/sanitized form when the original includes secrets, private URLs, local absolute paths, credentials, tokens, or personal data}

### Example 2
{examples[1] — omit this entire section if examples[1] does not exist; use the redacted/sanitized form when needed}

### Example 3
{examples[2] — omit this entire section if examples[2] does not exist; use the redacted/sanitized form when needed}

## Completion Evidence
- Generated preview states the concrete evidence required to consider the artifact complete.
- Verification evidence names the checks, commands, or review criteria used.
- Any residual risk or unverified assumption is listed explicitly.
```

Command preview:

```markdown
---
name: {command name}
description: {description}
---

Description of the /{command name} command behavior...

## Completion Evidence
- Command output includes the concrete success evidence.
- Verification evidence names the checks or commands used.
- Any residual risk or unverified assumption is listed explicitly.
```

Agent preview:

```markdown
---
name: {agent name}
description: {description}
model: claude-sonnet-4-6
---

# {agent name} agent

## Role
...

## Execution procedure
...

## Completion Evidence
- Agent output includes the concrete success evidence.
- Verification evidence names the checks, commands, or review criteria used.
- Any residual risk or unverified assumption is listed explicitly.
```

After the preview, ask:

```text
Create it as-is? (tell me what to change if you want edits)
```

## Name validation
- Skill names: English lowercase letters, numbers, and hyphen (`-`) only, following the official Skill spec, maximum 64 characters.
- Command and agent names: English lowercase letters, numbers, hyphen (`-`), and underscore (`_`) only.
- If special characters, spaces, or slashes are included, replace spaces with hyphens and remove the rest.
- Example: `"code review"` becomes `code-review`; `"PR/MR check"` becomes `pr-mr-check`.

## Path rules
| Type | Path |
| --- | --- |
| skill | `~/.claude/skills/{name}/SKILL.md` |
| command | `~/.claude/commands/{name}.md` |
| agent | `~/.claude/agents/{name}.md` |

For a skill:

```bash
mkdir -p ~/.claude/skills/{name}
```

Then write the previewed content with the file-write tool.

## Completion
After file creation:

1. Update the pattern status to `accepted` with generated artifact metadata.
2. Delete any pending file for that pid.
3. Print the completion message.

Completion message:

```text
The `{name}` {type} has been created: ~/.claude/{path}
You can use it starting from your next message.
```

Generated metadata fields:

- `status`: `accepted`
- `generated_type`: the selected type (`skill`, `command`, or `agent`)
- `generated_name`: the created artifact name
- `accepted_at`: current UTC timestamp formatted as `%Y-%m-%dT%H:%M:%SZ`

## Quality improvement loop (STEP E.5)

Right after the file is created, ask the user **once**:

```text
✅ `{name}` {type} created.
Run automatic quality improvement? [y/n]
```

### If approved

Call a different evaluator agent depending on the type:

| Type | Evaluator agent | Target path |
| --- | --- | --- |
| skill | `skill-evaluator` | `~/.claude/skills/{name}/SKILL.md` |
| command | `agent-evaluator-v2` | `~/.claude/commands/{name}.md` |
| agent | `agent-evaluator-v2` | `~/.claude/agents/{name}.md` |

```
Agent(
  subagent_type="{evaluator agent for the type}",
  prompt="Evaluate the following file and provide a 100-point score and line-level improvements: ~/.claude/{path}"
)
```

Handling the returned result:

- **80 or above**: No improvement needed. Print the score and proceed to STEP F.
- **Below 80**: Apply the suggested line-level improvements to the file immediately. After applying, print the improved final score and proceed to STEP F.

Completion output format:

```text
Quality improvement complete: {previous_score} → {final_score}
```

### If declined

Proceed directly to STEP F.

---

## Generation quality rules
1. Single responsibility: one skill means one clear job.
2. Clear trigger conditions: always state when to use the skill.
3. Few-shot examples: include three observed examples when available, but only after redacting or sanitizing secrets, private URLs, local absolute paths, credentials, tokens, and personal data.
4. Third-person descriptions: use forms like "a skill that ..." or "an agent responsible for ...".
5. Avoid over-abstraction: stay faithful to the observed pattern.
