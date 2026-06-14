# Pattern Scoring Reference

Load this reference for pending review, every 5-message threshold check, scoring/threshold checks, and manual `/skill-fog` listing.

## Five-message check
Claude tracks user-message count internally.

- Session start counter = 0.
- Increment by 1 for each user message.
- On multiples of 5 (5, 10, 15...), run pattern analysis silently.
- Do not tell the user analysis is running.

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

If the script prints `THRESHOLD_MET:...`, immediately print:

```text
**[skill-fog]** `{canonical}` 패턴이 {count}회 감지됐습니다.

예시:
- {examples[0]}
- {examples[1] — 없으면 이 줄 생략}

**skill / command / agent** 중 어떤 형태로 만들까요?
(건너뛰려면 '나중에')
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

When multiple pending files exist, sort by `snoozed_at` ascending, oldest first. Files without `snoozed_at` are treated as newly detected patterns and placed first. After the user finishes responding to one pattern, immediately propose the next pending pattern. Extract the pid by removing the `.json` extension from the file name.

Pending proposal text:

```text
**[skill-fog]** `{canonical}` 패턴이 {count}회({sessions 배열의 길이}개 세션)에서 감지되었습니다.

예시:
- {examples[0]}
- {examples[1] — 없으면 이 줄 생략}
- {examples[2] — 없으면 이 줄 생략}

**skill / command / agent** 중 어떤 형태로 만들까요?
(건너뛰려면 '나중에')
```

## Manual `/skill-fog`
Read current patterns:

```bash
cat ~/.skill-fog/patterns.json 2>/dev/null || echo '{"patterns":{}}'
```

Output:

```text
[skill-fog] 현재까지 감지된 패턴:

1. `{canonical}` — {count}회 / {sessions 배열의 길이}개 세션 / 상태: {status}
2. `{canonical}` — {count}회 / {sessions 배열의 길이}개 세션 / 상태: {status}
...

검토할 패턴 번호를 선택하세요. (없으면 '종료' — 일반 대화로 복귀)
```

When the user selects a number for an active pattern:

1. Show examples and ask: `**skill / command / agent** 중 어떤 형태로 만들까요? (건너뛰려면 '나중에')`
2. Add that pid to `session_proposed`.
3. Enter STEP B user-response handling.

Accepted/rejected patterns are shown for visibility but are not selectable.
