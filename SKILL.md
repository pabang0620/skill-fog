---
name: skill-fog
description: 반복 요청 패턴 감지 및 스킬/커맨드/에이전트 자동 생성. 세션 시작 시 ~/.skill-fog/pending/ 확인 후 감지된 패턴을 사용자에게 알리고 생성 여부 결정.
version: 1.0.0
triggers:
  - session_start
  - /skill-fog
---

# skill-fog 스킬

## 역할
Claude Code 사용자의 반복 요청 패턴을 감지하여 자동으로 스킬/커맨드/에이전트로 변환하는 도우미.

---

## STEP 1: 세션 시작 시 pending 확인

세션 시작 시 즉시 아래 절차를 실행한다.

```bash
ls ~/.skill-fog/pending/*.json 2>/dev/null
```

**pending 파일이 없으면**: 아무것도 하지 않는다. (조용히 패스)

**pending 파일이 있으면**: 각 파일을 읽어 사용자에게 알린다.

---

## STEP 2: 패턴 알림 메시지 형식

pending 파일 하나당 아래 형식으로 알린다:

```
**[skill-fog]** `{canonical}` 패턴이 {count}회({sessions}개 세션)에서 감지되었습니다.

예시:
- {examples[0]}
- {examples[1]}
- {examples[2]}

**skill / command / agent** 중 어떤 형태로 만들까요?
(건너뛰려면 '나중에' 또는 '스킵'이라고 입력하세요)
```

pending 파일이 여러 개면 하나씩 순서대로 제안한다.

---

## STEP 3: 사용자 응답 처리

### '나중에' / '스킵' / 'skip' / 'later' 입력 시
- pending 파일을 그대로 둔다.
- "다음 세션에 다시 제안할게요." 안내 후 종료.

### '거부' / '아니오' / '필요없어' 입력 시
- pending 파일 삭제.
- patterns.json의 해당 패턴 status를 'rejected'로 업데이트.

```bash
# pending 파일 삭제
rm ~/.skill-fog/pending/{PATTERN_ID}.json

# status 업데이트
jq --arg id "{PATTERN_ID}" \
  '.patterns[$id].status = "rejected"' \
  ~/.skill-fog/patterns.json > ~/.skill-fog/patterns.json.tmp \
  && mv ~/.skill-fog/patterns.json.tmp ~/.skill-fog/patterns.json
```

### 'skill' / 'command' / 'agent' 선택 시
→ STEP 4로 진행.

---

## STEP 4: 유사 항목 스캔

선택 전 기존 파일과 겹치는지 확인한다.

```bash
# 스킬 목록
find ~/.claude/skills/ -name "*.md" 2>/dev/null

# 커맨드 목록
find ~/.claude/commands/ -name "*.md" 2>/dev/null

# 에이전트 목록
find ~/.claude/agents/ -name "*.md" 2>/dev/null
```

**유사한 항목 발견 시**:
```
기존 `{기존_이름}`과 유사한 기능으로 보입니다.
- 합치기: 기존 파일에 이 패턴을 예시로 추가
- 별도 생성: 새 파일로 분리
어떻게 하시겠어요?
```

**유사 없음**: 바로 STEP 5로.

---

## STEP 5: 미리보기 생성 및 확인

실제 파일 생성 전, 내용을 미리 보여준다.

### skill 선택 시 미리보기 형식
```markdown
---
name: {자동생성_이름}
description: {3인칭으로 작성한 설명}
triggers:
  - {감지된 트리거 키워드들}
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
{examples[1]}

### 예시 3
{examples[2]}
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
model: claude-sonnet-4-5
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

## STEP 6: 실제 파일 생성

사용자 확인 후 파일을 생성한다.

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

## STEP 7: 완료 처리

생성 완료 후:

1. pending 파일 삭제:
```bash
rm ~/.skill-fog/pending/{PATTERN_ID}.json
```

2. patterns.json status 업데이트:
```bash
jq --arg id "{PATTERN_ID}" --arg type "{skill|command|agent}" \
  --arg name "{생성된_이름}" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.patterns[$id].status = "accepted" |
   .patterns[$id].generated_type = $type |
   .patterns[$id].generated_name = $name |
   .patterns[$id].accepted_at = $now' \
  ~/.skill-fog/patterns.json > ~/.skill-fog/patterns.json.tmp \
  && mv ~/.skill-fog/patterns.json.tmp ~/.skill-fog/patterns.json
```

3. 완료 메시지:
```
✓ `{이름}` {타입}이 생성되었습니다: ~/.claude/{경로}
다음 세션부터 바로 사용할 수 있습니다.
```

---

## 생성 품질 규칙

1. **단일 책임**: 하나의 스킬 = 하나의 명확한 일
2. **트리거 조건 명확히**: "언제 이 스킬을 사용하는가" 반드시 명시
3. **few-shot 예시 3개**: 관찰된 실제 예시를 그대로 포함
4. **description은 3인칭**: "~하는 스킬", "~를 담당하는 에이전트"
5. **과도한 추상화 금지**: 실제 관찰된 패턴에만 충실

---

## 수동 호출 (/skill-fog)

사용자가 `/skill-fog` 를 명시적으로 입력한 경우:
1. pending 파일 목록 출력
2. patterns.json에서 top 5 패턴 요약 출력
3. "검토하려는 패턴 번호를 선택하세요." 프롬프트
