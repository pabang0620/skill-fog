---
name: skill-fog
description: 반복 요청 패턴을 자동 감지하여 스킬/커맨드/에이전트 생성을 제안하는 스킬. SessionStart 훅이 세션 시작 시 pending 패턴을 자동 주입하며, 사용자가 /skill-fog를 명시적으로 호출할 때도 활성화된다.
version: 2.1.0
triggers:
  - /skill-fog
---

# skill-fog 스킬

## 역할
사용자의 반복 요청 패턴을 감지하여, 임계값 도달 시 스킬/커맨드/에이전트 생성을 제안하는 도우미.

## 활성화 조건
- **SessionStart 훅**이 세션 시작 시 pending 패턴을 컨텍스트에 자동 주입했을 때 → STEP A 실행
- 사용자가 `/skill-fog` 를 명시적으로 입력했을 때 → STEP A 실행

## 세션 시작 시 동작
SessionStart 훅(`~/.skill-fog/hooks/session-start.sh`)이 세션 시작(startup/resume) 시 자동 실행된다.
pending 패턴이 있으면 해당 정보가 컨텍스트에 주입되어 `[skill-fog] 검토 대기 중인 반복 패턴 N개가 있습니다.` 메시지가 보인다.
이 메시지가 보이면 즉시 STEP A를 실행한다.
STEP A에서 제안한 패턴의 pid를 세션 내부적으로 `session_proposed` 집합에 추가한다(이중 발동 방지).
세션이 새로 시작되면 `session_proposed`는 항상 빈 집합으로 초기화된다.

## 단계 라우팅

### STEP A: 세션 시작 시 pending 제안
pending 파일이 있을 때 실행한다. 각 파일은 pid 중복, `patterns.json` status, 정렬 순서, 메시지 형식을 [pattern-scoring.md](references/pattern-scoring.md)에 따라 처리한다.

### STEP B: 사용자 응답 처리
- `나중에` / `스킵` / `skip` / `later`: status를 `active`로 되돌리고 pending 파일을 생성하여 다음 세션에서 다시 제안한다.
- `거부` / `아니오` / `필요없어`: status를 `rejected`로 업데이트하고 pending 파일을 즉시 삭제한다.
- `skill` / `command` / `agent`: STEP C로 진행한다.

상태 전이와 파일 쓰기 절차는 [privacy-and-redaction.md](references/privacy-and-redaction.md)를 로드한다.

### STEP C: 유사 항목 스캔
선택 전 기존 skill, command, agent 파일과 겹치는지 확인한다. 스캔 경로와 유사 항목 발견 시 질문 형식은 [artifact-generation.md](references/artifact-generation.md)를 로드한다.

### STEP D: 미리보기 생성 및 확인
실제 파일 생성 전, 선택 타입별 미리보기를 보여준다. skill/command/agent 템플릿, examples 섹션 포함 규칙, 확인 질문은 [artifact-generation.md](references/artifact-generation.md)를 로드한다.

### STEP E: 실제 파일 생성
사용자 확인 후 파일을 생성한다. 이름 검증 규칙과 타입별 경로 규칙은 [artifact-generation.md](references/artifact-generation.md)를 로드한다.

### STEP E.5: 자동 품질 개선 (선택)
파일 생성 직후 사용자에게 1회 승인 요청한다. 승인 시 평가 에이전트를 호출하여 개선안을 적용한다. 승인 메시지, 에이전트 호출 방식, 점수 임계값, 개선 적용 절차는 [artifact-generation.md](references/artifact-generation.md)를 로드한다.

### STEP F: 완료 처리
생성 완료 후 `patterns.json` status를 `accepted`로 업데이트하고 pending 파일을 삭제한 뒤 완료 메시지를 출력한다. 정확한 업데이트 필드와 완료 메시지는 [artifact-generation.md](references/artifact-generation.md)를 로드한다.

## 수동 호출 (/skill-fog)
사용자가 `/skill-fog` 를 명시적으로 입력한 경우:

```bash
cat ~/.skill-fog/patterns.json 2>/dev/null || echo '{"patterns":{}}'
```

출력 형식, active 패턴 선택 처리, `session_proposed` 업데이트, STEP B 진입 조건은 [pattern-scoring.md](references/pattern-scoring.md)를 로드한다.

## 안전 규칙
- SKILL.md는 `patterns.json`을 읽기 전용으로 사용한다. 패턴 누적(count 증가, sessions 추가)은 `stop.sh`가 세션 종료 시에만 담당한다.
- pending-backed 패턴은 사용자가 명시적으로 수락하거나 거부하기 전까지 `active` 상태를 유지한다.
- 패턴 status가 `accepted` / `rejected`이면 새 pending을 생성하지 않는다.
- 같은 세션 내에서 이미 질문한 패턴은 다시 묻지 않는다.
- `rejected` 상태 패턴은 영구적으로 무시한다.
- 생성 품질 규칙은 [artifact-generation.md](references/artifact-generation.md)를 따른다.
- 민감정보, redaction, 원자적 쓰기, 로컬 파일 상태 전이는 [privacy-and-redaction.md](references/privacy-and-redaction.md)를 따른다.
- 문제 진단이 필요할 때만 [troubleshooting.md](references/troubleshooting.md)를 로드한다.

## Reference Loading
| 필요 상황 | 로드할 reference | 포함 내용 |
| --- | --- | --- |
| pending review, threshold checks, manual `/skill-fog` listing | [pattern-scoring.md](references/pattern-scoring.md) | 정규화, pid 생성, 임계값 조건, pending 정렬, 제안 메시지 |
| scoring/threshold checks | [pattern-scoring.md](references/pattern-scoring.md) | `THRESHOLD_MET`, `TRACKING`, `NO_DATA` 결과 해석 |
| artifact generation | [artifact-generation.md](references/artifact-generation.md) | 유사 항목 스캔, 미리보기 템플릿, 이름/경로 규칙, 완료 처리 |
| privacy/redaction, status updates, pending writes | [privacy-and-redaction.md](references/privacy-and-redaction.md) | active/rejected/accepted 전이, pending 생성/삭제, 원자적 JSON 쓰기 |
| troubleshooting | [troubleshooting.md](references/troubleshooting.md) | 누락 파일, 깨진 JSON, 중복 제안, pack/설치 문제 진단 |
