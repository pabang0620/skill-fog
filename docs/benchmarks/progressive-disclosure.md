# Progressive Disclosure Benchmark

Phase 2 moves long implementation details out of `SKILL.md` and into runtime-loaded references while preserving the original state-transition behavior.

## Size

Before Phase 2:

```text
419 13810 SKILL.md
```

After Phase 2:

```text
95 6281 SKILL.md
```

## Behavior Matrix

| Original behavior | New home | Notes |
| --- | --- | --- |
| Session-start pending check and `session_proposed` initialization | `SKILL.md`, `references/pattern-scoring.md` | Router keeps activation semantics; reference owns pending ordering and proposal text. |
| 5-message counter and quiet threshold analysis | `SKILL.md`, `references/pattern-scoring.md` | Router keeps summary; reference owns normalization and threshold script. |
| Normalization order and pid generation | `references/pattern-scoring.md` | UUID-before-number ordering preserved. |
| `THRESHOLD_MET`, `TRACKING`, `NO_DATA` handling | `references/pattern-scoring.md` | Threshold prompt format preserved. |
| Pending proposal ordering by `snoozed_at` | `references/pattern-scoring.md` | Missing `snoozed_at` still sorts before snoozed entries. |
| Manual `/skill-fog` listing and active-only selection | `SKILL.md`, `references/pattern-scoring.md` | Router keeps command entry; reference owns output and selection behavior. |
| `later` / `skip` response state transition | `SKILL.md`, `references/privacy-and-redaction.md` | Active status restoration and pending write preserved. |
| Reject response state transition | `SKILL.md`, `references/privacy-and-redaction.md` | Rejected status and pending deletion preserved. |
| Similar artifact scan | `references/artifact-generation.md` | Skill/command/agent scan paths preserved. |
| Preview templates | `references/artifact-generation.md` | Skill, command, and agent templates preserved. |
| Name validation and target paths | `references/artifact-generation.md` | Skill/command/agent naming rules preserved. |
| Accept response state transition | `SKILL.md`, `references/artifact-generation.md`, `references/privacy-and-redaction.md` | Accepted metadata fields and pending deletion preserved. |
| Generation quality rules | `SKILL.md`, `references/artifact-generation.md` | Router points to detailed quality rules. |
| Safety, duplicate prevention, and redaction guidance | `SKILL.md`, `references/privacy-and-redaction.md`, `references/troubleshooting.md` | Runtime state ownership remains explicit. |

## Verification Commands

```bash
wc -l -c SKILL.md
python3 - <<'PY'
from pathlib import Path
import re, sys
text = Path('SKILL.md').read_text(encoding='utf-8').splitlines()
fence = None
count = 0
errors = []
for i, line in enumerate(text, 1):
    m = re.match(r'^```(\w+)?\s*$', line)
    if not m:
        if fence:
            count += 1
        continue
    if not fence:
        fence = (m.group(1) or '', i)
        count = 0
    else:
        lang, start = fence
        if lang in {'bash', 'python'} and count > 20:
            errors.append(f'{lang} fence at line {start} has {count} lines')
        fence = None
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print('OK: no bash/python fenced block in SKILL.md exceeds 20 lines')
PY
python3 -m json.tool package.json
npm pack --dry-run --json
scripts/bench-hook.sh --assert-only
scripts/check-plan-structure.sh
```
