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
[skill-fog] "{canonical}" 패턴이 {count}회 반복됐어요.
추천: {타입} ({한 줄 이유}) — 바로 만들까요? (엔터로 확인 / 다른 타입 입력 / 안함)
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

When multiple pending files exist, sort by `snoozed_at` ascending, oldest first. Files without `snoozed_at` are treated as newly detected patterns and placed first.

**Before showing the list, classify each pattern into a recommended type using these rules:**

| 조건 | 추천 타입 | 이유 |
|------|-----------|------|
| 단순 반복 실행 ("해줘", "실행해", "확인해줘") | `command` | 한 번 실행하는 트리거성 작업 |
| 행동 지침·절차 기억 ("이렇게 해줘", "할 때마다") | `skill` | Claude 동작 방식 가이드 |
| 도구 사용·파일 탐색·분석 필요 ("분석해", "찾아줘", "정리해줘") | `agent` | 멀티스텝 자율 실행 필요 |
| 상태 복구·재개 ("계속진행해줘", "이어서 해줘") | `command` | 단발성 재개 트리거 |
| 프로젝트 컨텍스트 요약·파악 ("정리해봐", "파악했어?") | `command` | 현재 상태 즉시 조회 |

**Show ALL pending patterns at once with recommendations, then wait for the user's response.**

```text
[skill-fog] 반복 패턴 {N}개를 자동화할 수 있어요.

1. "{canonical}" ({count}회/{sessions}세션) → 추천: command (재개 트리거)
2. "{canonical}" ({count}회/{sessions}세션) → 추천: skill (배포 절차 기억)
3. "{canonical}" ({count}회/{sessions}세션) → 추천: agent (분석 필요)

추천대로 진행할까요? (엔터 또는 "자동")
개별 변경: "1 스킬, 3 안함" 처럼 입력
```

- 사용자가 엔터 or "자동" or "응" → 모든 패턴을 추천 타입으로 일괄 생성
- 개별 응답 시 해당 항목만 변경, 나머지는 추천 타입 적용
- "안함"으로 지정한 항목은 STEP B에서 rejected 처리

User responds, then enter STEP B per item.

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
