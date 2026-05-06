---
name: skill-fog
description: 대화 중 반복 요청 패턴을 자동 감지하여 스킬/커맨드/에이전트 생성을 제안하는 스킬. 매 5번째 메시지마다 자동 실행되며, 동일 패턴이 3회 이상·2개 이상 세션에서 감지될 때 즉시 제안한다. 사용자가 /skill-fog를 명시적으로 호출하거나 세션 시작 시 pending 패턴이 있을 때도 활성화된다.
version: 2.0.4
triggers:
  - /skill-fog
---

# skill-fog 스킬

## 역할
Claude Code 대화 중 사용자의 반복 요청 패턴을 실시간으로 감지하여, 임계값 도달 시 즉시 스킬/커맨드/에이전트 생성을 제안하는 도우미.

---

## 세션 시작 시 초기화

세션이 시작되면 즉시 pending 파일을 확인한다.

```bash
ls ~/.skill-fog/pending/*.json 2>/dev/null
```

pending 파일이 있으면 STEP A(pending 제안)를 먼저 실행한다.
STEP A에서 제안한 패턴의 pid를 세션 내부적으로 `session_proposed` 집합에 추가한다.
이후 5번째 메시지 체크 시 `session_proposed`에 포함된 pid는 건너뛴다 (이중 발동 방지).
세션이 새로 시작되면 `session_proposed`는 항상 빈 집합으로 초기화된다.
없으면 아무것도 하지 않고 조용히 대기한다.

---

## 핵심 동작: 5개 메시지마다 패턴 분석

Claude는 대화 중 사용자 메시지 수를 내부적으로 추적한다.

- 세션 시작 시 카운터 = 0
- 사용자 메시지가 올 때마다 카운터 +1
- **카운터가 5의 배수(5, 10, 15...)일 때** 아래 패턴 분석을 실행한다
- 분석 중임을 사용자에게 알리지 않는다 (조용히 실행)

### 패턴 분석 절차

**1단계: 직전 5개 사용자 메시지를 각각 개별 정규화**

stop.sh와 동일한 정규화 규칙 (아래 순서대로 적용):
- 소문자 변환
- 파일명(확장자 포함) → `FILE`
- UUID → `UUID`  ← 반드시 숫자 치환(NUM)보다 먼저
- URL → `URL`
- 숫자 → `NUM`
- 공백 정규화, 120자 이하로 자름

예: `"UserList.tsx 리팩토링해줘"` → `"FILE 리팩토링해줘"`

**2단계: 각 메시지별로 개별 패턴 ID 생성 후 patterns.json 조회 (읽기 전용)**

아래 코드를 실행한다. `MSG1`~`MSG5`는 직전 5개 사용자 메시지 원본으로 교체한다.

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

# Claude가 실제 직전 5개 사용자 메시지로 교체
messages = ['MSG1', 'MSG2', 'MSG3', 'MSG4', 'MSG5']
# 세션 내 이미 제안한 pid 집합. 아래 두 경로에서 누적:
# (1) STEP A 실행 시: 각 pending의 pid를 추가 (건너뛴 경우 포함)
# (2) 3단계 THRESHOLD_MET 처리 시: 해당 pid를 추가
# Claude는 이 set을 세션 전체에서 유지하며 5번째 체크마다 참조한다.
# 예: {'0f8f542d3137', 'ce312bede3b4'}
session_proposed = set()  # 실제 세션 제안 이력으로 교체

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
    # session_proposed: 이번 세션에서 이미 제안한 pid 집합 (Claude 내부 추적)
    if p and p.get('count', 0) >= 3 and len(p.get('sessions', [])) >= 2 and p.get('status') == 'active' and pid not in session_proposed:
        print(f"THRESHOLD_MET:{pid}:{p['canonical'][:60]}:{p['count']}:{json.dumps(p.get('examples', [])[:2])}")
        sys.exit(0)
print('TRACKING')
```

**3단계: 임계값 도달 시 즉시 질문**

2단계 결과가 `THRESHOLD_MET:...`이면 즉시 아래 메시지를 출력한다:

```
**[skill-fog]** `{canonical}` 패턴이 {count}회 감지됐습니다.

예시:
- {examples[0]}
- {examples[1] — 없으면 이 줄 생략}

**skill / command / agent** 중 어떤 형태로 만들까요?
(건너뛰려면 '나중에')
```

그리고 patterns.json의 해당 패턴 status를 `proposed`로 업데이트하고, 해당 pid를 `session_proposed`에 추가한다 (이중 발동 방지):

```bash
python3 -c "
import json, os
pf = os.path.expanduser('~/.skill-fog/patterns.json')
pid = 'PATTERN_ID'  # 위 2단계에서 얻은 실제 pattern id로 교체
with open(pf) as f:
    d = json.load(f)
if pid in d['patterns']:
    d['patterns'][pid]['status'] = 'proposed'
with open(pf + '.tmp', 'w') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
os.replace(pf + '.tmp', pf)
"
```

> **중요**: SKILL.md는 patterns.json을 **읽기 전용**으로 사용한다. 패턴 누적(count 증가, sessions 추가)은 stop.sh가 세션 종료 시에만 담당한다. SKILL.md는 이미 누적된 데이터를 체크하고, status를 'proposed'로 변경하는 것만 허용된다.

---

## STEP A: 세션 시작 시 pending 제안

pending 파일이 있을 때 실행한다.

각 파일에 대해 아래 순서로 처리한다:
1. pid가 `session_proposed`에 있으면 건너뛴다.
2. `patterns.json`에서 해당 pid의 status를 확인한다:
   - `accepted` 또는 `rejected`: pending 파일을 삭제하고 건너뛴다.
   - `proposed`: `session_proposed`에 pid를 추가하고 건너뛴다 (stop.sh가 이미 처리 중).
   - `active` (또는 status 필드 없음): 제안을 진행한다.
세션 시작 시 `session_proposed`는 빈 집합이므로 조건 1은 모든 pending에 열려 있다.

각 파일을 읽어 아래 형식으로 알린다:

```
**[skill-fog]** `{canonical}` 패턴이 {count}회({sessions 배열의 길이}개 세션)에서 감지되었습니다.

예시:
- {examples[0]}
- {examples[1] — 없으면 이 줄 생략}
- {examples[2] — 없으면 이 줄 생략}

**skill / command / agent** 중 어떤 형태로 만들까요?
(건너뛰려면 '나중에')
```

pending 파일이 여러 개면 `snoozed_at` 오름차순(오래된 것 먼저)으로 정렬하여 하나씩 순서대로 제안한다.
`snoozed_at` 필드가 없는 파일(신규 감지 패턴)은 목록 앞쪽에 배치한다. 각 패턴 응답 완료 후 다음 pending을 즉시 이어서 제안한다.
pid는 파일명에서 `.json` 확장자를 제거하여 추출한다.

---

## STEP B: 사용자 응답 처리

### '나중에' / '스킵' / 'skip' / 'later' 입력 시
- patterns.json의 해당 패턴 status를 `active`로 되돌리고, pending 파일을 생성하여 다음 세션에서 다시 제안되도록 한다.

```bash
python3 -c "
import json, os
from datetime import datetime, timezone
pf = os.path.expanduser('~/.skill-fog/patterns.json')
pid = 'PATTERN_ID'
pending_dir = os.path.expanduser('~/.skill-fog/pending')
os.makedirs(pending_dir, exist_ok=True)
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
with open(pf) as f: d = json.load(f)
p = d['patterns'].get(pid, {})
if p:
    d['patterns'][pid]['status'] = 'active'
    with open(pf+'.tmp','w') as f: json.dump(d,f,ensure_ascii=False,indent=2)
    os.replace(pf+'.tmp', pf)
    pending_data = {'pid': pid, 'canonical': p.get('canonical',''), 'count': p.get('count',0), 'sessions': p.get('sessions',[]), 'examples': p.get('examples',[]), 'snoozed_at': now}
    with open(os.path.join(pending_dir, pid+'.json'),'w') as f: json.dump(pending_data,f,ensure_ascii=False,indent=2)
"
```

- "알겠습니다. 다음 세션에서 다시 확인할게요." 안내 후 종료.

### '거부' / '아니오' / '필요없어' 입력 시
- patterns.json의 해당 패턴 status를 'rejected'로 업데이트하고, pending 파일을 즉시 삭제한다.

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

### 'skill' / 'command' / 'agent' 선택 시
→ STEP C로 진행.

---

## STEP C: 유사 항목 스캔

선택 전 기존 파일과 겹치는지 확인한다.

```bash
find ~/.claude/skills/ -name "*.md" 2>/dev/null
find ~/.claude/commands/ -name "*.md" 2>/dev/null
find ~/.claude/agents/ -name "*.md" 2>/dev/null
```

**유사한 항목 발견 시**:
```
기존 `{기존_이름}`과 유사한 기능으로 보입니다.
- 합치기: 기존 파일에 이 패턴을 예시로 추가
- 별도 생성: 새 파일로 분리
어떻게 하시겠어요?
```

**유사 없음**: 바로 STEP D로.

---

## STEP D: 미리보기 생성 및 확인

실제 파일 생성 전, 내용을 미리 보여준다.

### skill 선택 시 미리보기 형식

examples 수에 따라 포함할 섹션을 결정한다:
- examples[0]은 항상 포함
- examples[1]이 있으면 "예시 2" 섹션 추가
- examples[2]가 있으면 "예시 3" 섹션 추가

```markdown
---
name: {자동생성_이름}
description: {3인칭으로 작성한 설명}
---

# {스킬명}

## 역할
{관찰된 패턴 기반 역할 설명}

## 언제 사용하나
{트리거 조건 - 명확하게}

## 동작 방식
{단계별 절차}

## 예시
### 예시 1
{examples[0]}

### 예시 2
{examples[1] — examples[1]이 없으면 이 섹션 전체 생략}

### 예시 3
{examples[2] — examples[2]가 없으면 이 섹션 전체 생략}
```

### command 선택 시 미리보기 형식
```markdown
---
name: {커맨드명}
description: {설명}
---

/{커맨드명} 커맨드 동작 설명...
```

### agent 선택 시 미리보기 형식
```markdown
---
name: {에이전트명}
description: {설명}
model: claude-sonnet-4-6
---

# {에이전트명} 에이전트

## 역할
...

## 실행 절차
...
```

미리보기 후:
```
이대로 생성할까요? (수정하려면 원하는 내용을 말씀해주세요)
```

---

## STEP E: 실제 파일 생성

사용자 확인 후 파일을 생성한다.

### 이름 검증 규칙

- **skill 타입**: 영문 소문자, 숫자, 하이픈(-)만 허용 (공식 Skill 규격, 64자 이하).
- **command / agent 타입**: 영문 소문자, 숫자, 하이픈(-), 언더스코어(_) 허용.
- 특수문자/공백/슬래시 포함 시 자동 치환: 공백→하이픈, 나머지→제거.
- 예: "코드 리뷰" → "code-review", "PR/MR check" → "pr-mr-check"

### 경로 규칙
| 타입 | 경로 |
|------|------|
| skill | `~/.claude/skills/{이름}/SKILL.md` |
| command | `~/.claude/commands/{이름}.md` |
| agent | `~/.claude/agents/{이름}.md` |

```bash
# 예: skill 생성
mkdir -p ~/.claude/skills/{이름}
# 파일 내용 작성 (Write 도구 사용)
```

---

## STEP F: 완료 처리

생성 완료 후:

1. patterns.json status 업데이트:

```bash
python3 -c "
import json, os
from datetime import datetime, timezone
pf = os.path.expanduser('~/.skill-fog/patterns.json')
pid = 'PATTERN_ID'
gtype = 'skill'  # 실제 선택된 타입으로 교체
gname = '생성된_이름'  # 실제 생성된 이름으로 교체
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
with open(pf) as f: d = json.load(f)
if pid in d['patterns']:
    d['patterns'][pid].update({'status':'accepted','generated_type':gtype,'generated_name':gname,'accepted_at':now})
with open(pf+'.tmp','w') as f: json.dump(d,f,ensure_ascii=False,indent=2)
os.replace(pf+'.tmp', pf)
"
```

2. pending 파일이 있으면 삭제:

```bash
rm -f ~/.skill-fog/pending/{PATTERN_ID}.json
```

3. 완료 메시지:

```
`{이름}` {타입}이 생성되었습니다: ~/.claude/{경로}
다음 메시지부터 바로 사용할 수 있습니다.
```

---

## 생성 품질 규칙

1. **단일 책임**: 하나의 스킬 = 하나의 명확한 일
2. **트리거 조건 명확히**: "언제 이 스킬을 사용하는가" 반드시 명시
3. **few-shot 예시 3개**: 관찰된 실제 예시를 그대로 포함
4. **description은 3인칭**: "~하는 스킬", "~를 담당하는 에이전트"
5. **과도한 추상화 금지**: 실제 관찰된 패턴에만 충실

---

## 중복 방지 규칙

- 패턴 status가 `proposed` / `accepted` / `rejected`이면 새 pending을 생성하지 않는다. (count 누적은 stop.sh가 status 무관하게 처리하며, 5번째 체크 및 pending 생성은 status=`active` 패턴에만 동작한다.)
- 같은 세션 내에서 이미 질문한 패턴은 다시 묻지 않는다.
- `rejected` 상태 패턴은 영구적으로 무시한다.

---

## 수동 호출 (/skill-fog)

사용자가 `/skill-fog` 를 명시적으로 입력한 경우:

```bash
cat ~/.skill-fog/patterns.json 2>/dev/null || echo '{"patterns":{}}'
```

출력 형식:
```
[skill-fog] 현재까지 감지된 패턴:

1. `{canonical}` — {count}회 / {sessions 배열의 길이}개 세션 / 상태: {status}
2. `{canonical}` — {count}회 / {sessions 배열의 길이}개 세션 / 상태: {status}
...

검토할 패턴 번호를 선택하세요. (없으면 '종료' — 일반 대화로 복귀)
번호 선택 시 (status가 active인 패턴만):
1. 해당 패턴의 예시를 표시하고 아래 질문을 출력한다:
   "**skill / command / agent** 중 어떤 형태로 만들까요? (건너뛰려면 '나중에')"
2. 해당 pid를 `session_proposed`에 추가한다. (이중 발동 방지)
3. 사용자 응답에 따라 STEP B(사용자 응답 처리) 진입.
(proposed/accepted/rejected 상태 패턴은 상태만 표시하고 선택 불가)
```
