# Pattern Scoring Reference

Load this reference for pending review, scoring/threshold checks, and manual `/skill-fog` listing.

## Normalization
Normalize each of the previous 5 user messages independently, using the same rule order as `stop.sh`:

1. Convert to lowercase.
2. Replace filenames with extensions with `FILE`.
3. Replace UUIDs with `UUID`; this must happen before numeric replacement.
4. Replace URLs with `URL`.
5. Replace numbers with `NUM`.
6. Normalize whitespace and truncate to 120 characters.

Example: `"UserList.tsx 리팩토링해줘"` becomes `"FILE 리팩토링해줘"`.

```python
import hashlib, json, os, re, sys

def normalize(msg):
    msg = msg.lower()
    msg = re.sub(r'[a-zA-Z0-9_/\-]+\.(tsx|ts|jsx|json|yaml|js|yml|py|md|sh|env|toml)', 'FILE', msg)
    msg = re.sub(r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}', 'UUID', msg)
    msg = re.sub(r'https?://[^ ]+', 'URL', msg)
    msg = re.sub(r'[0-9]+', 'NUM', msg)
    msg = re.sub(r'\s+', ' ', msg).strip()
    return msg[:120]

messages = ['MSG1', 'MSG2', 'MSG3', 'MSG4', 'MSG5']
session_proposed = set()
patterns_file = os.path.expanduser('~/.skill-fog/patterns.json')
try:
    with open(patterns_file) as f:
        data = json.load(f)
except Exception:
    print('NO_DATA'); sys.exit(0)

patterns = data.get('patterns', {})
for msg in messages:
    if len(msg) < 10:
        continue
    canonical = normalize(msg)
    if not canonical:
        continue
    pid = hashlib.md5(canonical.encode()).hexdigest()[:12]
    p = patterns.get(pid)
    if p and p.get('count', 0) >= 3 and len(p.get('sessions', [])) >= 2 and p.get('status') == 'active' and pid not in session_proposed:
        print(f"THRESHOLD_MET:{pid}:{p['canonical'][:60]}:{p['count']}:{json.dumps(p.get('examples', [])[:2])}")
        sys.exit(0)
print('TRACKING')
```

`session_proposed` is maintained by Claude for the whole session and contains only pids actually proposed to the user in the current session. It is populated from two sources:

- STEP A execution: add each pending pid only after its proposal is shown to the user.
- THRESHOLD_MET handling: add the pid that was proposed.

If the script prints `THRESHOLD_MET:...`, immediately print (translated into the user's language):

```text
[skill-fog] The pattern "{canonical}" has repeated {count} times.
Recommended: {type} ({one-line reason}) — create it now? (Enter to confirm / type another type / skip)
```

Then add that pid to `session_proposed` to prevent duplicate firing.

## Pending review at session start
When pending files exist, process each file in this order:

1. If pid is already in `session_proposed`, skip it.
2. Check that pid in `patterns.json`:
   - `accepted` or `rejected`: delete the pending file and skip.
   - `active` or missing status: continue with the proposal.
3. Show the proposal text.
4. Add the pid to `session_proposed`.

At session start, `session_proposed` is empty, so condition 1 is open to all pending entries.

When multiple pending files exist, they are already sorted by `count` descending (highest repeat count first), matching `hooks/session-start.sh`. Preserve this order when showing the proposal list; do not re-sort by `snoozed_at`.

**Before showing the list, classify each pattern into a recommended type using these rules:**

| Condition | Recommended type | Reason |
|------|-----------|------|
| Simple repeated execution ("do X", "run X", "check X") | `command` | A one-shot trigger task |
| Remembering behavior/procedure ("do it like this", "every time you...") | `skill` | Guides how Claude behaves |
| Needs tool use / file exploration / analysis ("analyze", "find", "organize") | `agent` | Needs multi-step autonomous execution |
| State recovery / resumption ("continue", "resume from where we left off") | `command` | A one-shot resume trigger |
| Project context summary / understanding ("summarize", "did you get the gist?") | `command` | Instant current-state lookup |

**Show ALL pending patterns at once with recommendations, then wait for the user's response. Translate the message into the user's language.**

```text
[skill-fog] I can automate {N} repeated pattern(s).

1. "{canonical}" ({count}x/{sessions} sessions) → recommended: command (resume trigger)
2. "{canonical}" ({count}x/{sessions} sessions) → recommended: skill (remember deploy steps)
3. "{canonical}" ({count}x/{sessions} sessions) → recommended: agent (needs analysis)

Proceed with the recommendations? (Enter or "auto")
To change individually: type e.g. "1 skill, 3 none"
```

- User presses Enter / "auto" / "yes" → generate every pattern with its recommended type
- On an individual response, change only that item; apply the recommended type to the rest
- Items marked "none" / "skip" are handled as rejected in STEP B

User responds, then enter STEP B per item.

## Manual `/skill-fog`
Read current patterns:

```bash
cat ~/.skill-fog/patterns.json 2>/dev/null || echo '{"patterns":{}}'
```

Output (translate into the user's language):

```text
[skill-fog] Patterns detected so far:

1. `{canonical}` — {count}x / {length of sessions array} session(s) / status: {status}
2. `{canonical}` — {count}x / {length of sessions array} session(s) / status: {status}
...

Pick a pattern number to review. (Type 'exit' if none — return to normal conversation.)
```

When the user selects a number for an active or snoozed pattern:

1. Show examples and ask: `Which form should I create — **skill / command / agent**? (type 'later' to skip)`
2. Add that pid to `session_proposed`.
3. Enter STEP B user-response handling.

A `snoozed` pattern was proposed in a previous session but ignored. Handle it the same as an `active` pattern.

Accepted/rejected patterns are shown for visibility but are not selectable.
