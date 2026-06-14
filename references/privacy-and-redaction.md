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
For `나중에`, `스킵`, `skip`, or `later`:

- Set the pattern status back to `active`.
- Create or replace the pending file so the next session proposes it again.
- Include `snoozed_at` with current UTC timestamp formatted as `%Y-%m-%dT%H:%M:%SZ`.
- Tell the user: `알겠습니다. 다음 세션에서 다시 확인할게요.`

```python
import json, os
from datetime import datetime, timezone

pf = os.path.expanduser('~/.skill-fog/patterns.json')
pid = 'PATTERN_ID'
pending_dir = os.path.expanduser('~/.skill-fog/pending')
os.makedirs(pending_dir, exist_ok=True)
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
with open(pf) as f:
    d = json.load(f)
p = d['patterns'].get(pid, {})
if p:
    d['patterns'][pid]['status'] = 'active'
    with open(pf + '.tmp', 'w') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    os.replace(pf + '.tmp', pf)
    pending_data = {'pid': pid, 'canonical': p.get('canonical', ''), 'count': p.get('count', 0), 'sessions': p.get('sessions', []), 'examples': p.get('examples', []), 'status': 'active', 'snoozed_at': now}
    with open(os.path.join(pending_dir, pid + '.json'), 'w') as f:
        json.dump(pending_data, f, ensure_ascii=False, indent=2)
```

## Reject response
For `거부`, `아니오`, or `필요없어`:

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
gname = '생성된_이름'
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
