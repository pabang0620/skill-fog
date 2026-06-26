# Artifact Generation Reference

Load this reference when the user chooses `skill`, `command`, or `agent`.

## Similar item scan
Before generating a preview, check whether the requested artifact overlaps with existing files.

```bash
find ~/.claude/skills/ -name "*.md" 2>/dev/null
find ~/.claude/commands/ -name "*.md" 2>/dev/null
find ~/.claude/agents/ -name "*.md" 2>/dev/null
```

If a similar item is found, ask:

```text
기존 `{기존_이름}`과 유사한 기능으로 보입니다.
- 합치기: 기존 파일에 이 패턴을 예시로 추가
- 별도 생성: 새 파일로 분리
어떻게 하시겠어요?
```

If no similar item is found, proceed directly to preview generation.

## Preview generation
Show a preview before creating a file.

For skill previews, include sections based on available examples:

- `examples[0]` is always included.
- Add the "예시 2" section only when `examples[1]` exists.
- Add the "예시 3" section only when `examples[2]` exists.

Skill preview:

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
{examples[0] — use the redacted/sanitized form when the original includes secrets, private URLs, local absolute paths, credentials, tokens, or personal data}

### 예시 2
{examples[1] — examples[1]이 없으면 이 섹션 전체 생략; use the redacted/sanitized form when needed}

### 예시 3
{examples[2] — examples[2]가 없으면 이 섹션 전체 생략; use the redacted/sanitized form when needed}

## Completion Evidence
- Generated preview states the concrete evidence required to consider the artifact complete.
- Verification evidence names the checks, commands, or review criteria used.
- Any residual risk or unverified assumption is listed explicitly.
```

Command preview:

```markdown
---
name: {커맨드명}
description: {설명}
---

/{커맨드명} 커맨드 동작 설명...

## Completion Evidence
- Command output includes the concrete success evidence.
- Verification evidence names the checks or commands used.
- Any residual risk or unverified assumption is listed explicitly.
```

Agent preview:

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

## Completion Evidence
- Agent output includes the concrete success evidence.
- Verification evidence names the checks, commands, or review criteria used.
- Any residual risk or unverified assumption is listed explicitly.
```

After the preview, ask:

```text
이대로 생성할까요? (수정하려면 원하는 내용을 말씀해주세요)
```

## Name validation
- Skill names: English lowercase letters, numbers, and hyphen (`-`) only, following the official Skill spec, maximum 64 characters.
- Command and agent names: English lowercase letters, numbers, hyphen (`-`), and underscore (`_`) only.
- If special characters, spaces, or slashes are included, replace spaces with hyphens and remove the rest.
- Example: `"코드 리뷰"` becomes `code-review`; `"PR/MR check"` becomes `pr-mr-check`.

## Path rules
| Type | Path |
| --- | --- |
| skill | `~/.claude/skills/{이름}/SKILL.md` |
| command | `~/.claude/commands/{이름}.md` |
| agent | `~/.claude/agents/{이름}.md` |

For a skill:

```bash
mkdir -p ~/.claude/skills/{이름}
```

Then write the previewed content with the file-write tool.

## Completion
After file creation:

1. Update the pattern status to `accepted` with generated artifact metadata.
2. Delete any pending file for that pid.
3. Print the completion message.

Completion message:

```text
`{이름}` {타입}이 생성되었습니다: ~/.claude/{경로}
다음 메시지부터 바로 사용할 수 있습니다.
```

Generated metadata fields:

- `status`: `accepted`
- `generated_type`: the selected type (`skill`, `command`, or `agent`)
- `generated_name`: the created artifact name
- `accepted_at`: current UTC timestamp formatted as `%Y-%m-%dT%H:%M:%SZ`

## 품질 개선 루프 (STEP E.5)

파일 생성 완료 직후 사용자에게 **1회만** 묻는다:

```text
✅ `{이름}` {타입} 생성 완료.
자동 품질 개선을 실행할까요? [y/n]
```

### 승인한 경우

타입에 따라 다른 평가 에이전트를 호출한다:

| 타입 | 평가 에이전트 | 평가 대상 경로 |
| --- | --- | --- |
| skill | `skill-evaluator` | `~/.claude/skills/{이름}/SKILL.md` |
| command | `agent-evaluator-v2` | `~/.claude/commands/{이름}.md` |
| agent | `agent-evaluator-v2` | `~/.claude/agents/{이름}.md` |

```
Agent(
  subagent_type="{타입별 평가 에이전트}",
  prompt="다음 파일을 평가하고 100점 척도 점수와 라인 단위 개선안을 제공해주세요: ~/.claude/{경로}"
)
```

반환된 결과 처리:

- **80점 이상**: 개선 불필요. 점수를 출력하고 STEP F로 진행.
- **80점 미만**: 제안된 라인 단위 개선안을 파일에 즉시 반영한다. 반영 후 개선된 최종 점수를 출력하고 STEP F로 진행.

완료 출력 형식:

```text
품질 개선 완료: {이전_점수}점 → {최종_점수}점
```

### 거부한 경우

즉시 STEP F로 진행한다.

---

## Generation quality rules
1. Single responsibility: one skill means one clear job.
2. Clear trigger conditions: always state when to use the skill.
3. Few-shot examples: include three observed examples when available, but only after redacting or sanitizing secrets, private URLs, local absolute paths, credentials, tokens, and personal data.
4. Third-person descriptions: use forms like "~하는 스킬" or "~를 담당하는 에이전트".
5. Avoid over-abstraction: stay faithful to the observed pattern.
