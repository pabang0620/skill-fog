# Privacy And Redaction Reference

Load this reference for status transitions, pending file writes/deletes, local state mutation, privacy-sensitive examples, and redaction decisions.

## State ownership
- `SKILL.md` reads `patterns.json` for threshold and manual review decisions.
- Pattern accumulation (`count` increments and `sessions` additions) is owned only by `stop.sh` at session end.
- Pending-backed patterns stay `active` until the user explicitly accepts or rejects them.
- `accepted` and `rejected` patterns must not create new pending proposals.
- `rejected` patterns are permanently ignored.

## Before user accepts or rejects
If a threshold-backed or pending-backed proposal is shown, keep the pattern active:

```bash
python3 -c "
import json, os
pf = os.path.expanduser('~/.skill-fog/patterns.json')
pid = 'PATTERN_ID'
with open(pf) as f:
    d = json.load(f)
if pid in d['patterns']:
    d['patterns'][pid]['status'] = 'active'
with open(pf + '.tmp', 'w') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
os.replace(pf + '.tmp', pf)
"
```

## Later / skip response
For `later`, `skip`, `나중에`, or `스킵`:

- The SessionStart hook already moved the pattern to `snoozed` and removed the pending file when it was proposed, so **no state change is needed**.
- Do not re-create the pending file. A `snoozed` pattern is not re-proposed automatically next session.
- Tell the user (in their language): `Got it. It won't come up again automatically — run /skill-fog anytime to revisit it.`

(If for any reason the status is still `active` and a pending file remains, set the status to `snoozed` and delete the pending file so it is not re-proposed.)

```python
import json, os

pf = os.path.expanduser('~/.skill-fog/patterns.json')
pid = 'PATTERN_ID'
pending_dir = os.path.expanduser('~/.skill-fog/pending')
with open(pf) as f:
    d = json.load(f)
if pid in d['patterns'] and d['patterns'][pid].get('status') == 'active':
    d['patterns'][pid]['status'] = 'snoozed'
    with open(pf + '.tmp', 'w') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    os.replace(pf + '.tmp', pf)
pending_file = os.path.join(pending_dir, pid + '.json')
if os.path.exists(pending_file):
    os.remove(pending_file)
```

## Reject response
For `reject`, `no`, `거부`, or `아니오`:

- Set the pattern status to `rejected`.
- Delete the pending file immediately.

```bash
python3 -c "
import json, os
pf = os.path.expanduser('~/.skill-fog/patterns.json')
pid = 'PATTERN_ID'
with open(pf) as f: d = json.load(f)
if pid in d['patterns']: d['patterns'][pid]['status'] = 'rejected'
with open(pf+'.tmp','w') as f: json.dump(d,f,ensure_ascii=False,indent=2)
os.replace(pf+'.tmp', pf)
"

rm -f ~/.skill-fog/pending/{PATTERN_ID}.json
```

## Accept response
After artifact creation, update the status to `accepted` and persist artifact metadata:

```bash
python3 -c "
import json, os
from datetime import datetime, timezone
pf = os.path.expanduser('~/.skill-fog/patterns.json')
pid = 'PATTERN_ID'
gtype = 'skill'
gname = 'generated_name'
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
with open(pf) as f: d = json.load(f)
if pid in d['patterns']:
    d['patterns'][pid].update({'status':'accepted','generated_type':gtype,'generated_name':gname,'accepted_at':now})
with open(pf+'.tmp','w') as f: json.dump(d,f,ensure_ascii=False,indent=2)
os.replace(pf+'.tmp', pf)
"
```

Then delete pending state:

```bash
rm -f ~/.skill-fog/pending/{PATTERN_ID}.json
```

## Redaction guidance
- Do not add new raw examples beyond the examples already stored by skill-fog state.
- Preserve observed examples in generated artifact previews only as redacted or sanitized examples when they contain secrets, tokens, local absolute paths, private URLs, credentials, or personal data.
- Never copy raw secrets or private values from state into generated artifact previews, docs, benchmark evidence, or completion reports.
- When editing generated descriptions, avoid adding secrets, tokens, local absolute paths, private URLs, or credentials.
- Keep all state writes local to `~/.skill-fog` and artifact writes local to `~/.claude`.
- Use temp-file plus `os.replace` for JSON updates to avoid partial writes.
