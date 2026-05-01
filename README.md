# skill-fog

> Claude Code 사용자의 반복 요청 패턴을 감지하여 스킬·커맨드·에이전트를 자동 생성하는 도구.
>
> Automatically detects repetitive usage patterns in Claude Code and generates skills, commands, and agents.

---

## 개요 / Overview

Claude Code를 사용하다 보면 같은 요청을 반복하게 됩니다. skill-fog는 이런 패턴을 조용히 추적하다가 일정 임계값을 넘으면 "이거 스킬로 만들까요?"라고 제안합니다.

When using Claude Code, you often find yourself making the same requests repeatedly. skill-fog silently tracks these patterns and, once a threshold is crossed, asks: "Want to turn this into a skill?"

**동작 방식:**
1. 세션 종료 시 Claude Code Stop 훅이 사용자 메시지를 분석
2. 동일 패턴이 **3회 이상, 2개 이상 세션**에서 감지되면 pending으로 승격
3. 다음 세션 시작 시 Claude가 패턴을 알리고 skill / command / agent 생성 제안
4. 사용자 확인 후 `~/.claude/` 경로에 파일 자동 생성

---

## 설치 / Installation

### npm (권장 / Recommended)

```bash
npm install -g skill-fog
```

### curl (직접 설치 / Direct install)

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/skill-fog/main/install.sh | bash
```

### 수동 설치 / Manual

```bash
git clone https://github.com/YOUR_USERNAME/skill-fog.git
cd skill-fog
bash install.sh
```

**의존성 / Dependencies:**
- `jq` (권장) 또는 `python3` (fallback)
- `bash >= 4.0`
- Claude Code

---

## 사용법 / Usage

### CLI

```bash
# 패턴 현황 확인
skill-fog status

# 대기 중인 패턴 검토 및 처리
skill-fog review

# 생성된 스킬/커맨드/에이전트 목록
skill-fog list

# 오래된/거부된 패턴 정리
skill-fog clean

# 설치 진단
skill-fog doctor
```

### Claude Code 내에서

```
/skill-fog
```

세션 시작 시 pending 패턴이 있으면 자동으로 알림이 표시됩니다.

Pending patterns are automatically surfaced at session start.

---

## 동작 원리 / How It Works

```
Claude Code Session
       │
       ▼
  [Stop Hook]  ← ~/.skill-fog/hooks/stop.sh
       │
       ▼
  stdin으로 세션 페이로드 수신
  사용자 메시지 추출 + 시크릿 마스킹
       │
       ▼
  정규화 (소문자, 파일명/숫자 제거)
  MD5 해시로 패턴 ID 생성
       │
       ▼
  ~/.skill-fog/patterns.json 업데이트
       │
       ├─ count < 3 → 계속 수집
       │
       └─ count >= 3, sessions >= 2
              │
              ▼
         ~/.skill-fog/pending/{id}.json 생성
              │
              ▼
         다음 세션 시작 시 Claude가 제안
              │
         [skill / command / agent / 나중에]
              │
              ▼
         ~/.claude/skills|commands|agents/ 생성
```

### 데이터 파일 구조 / Data Files

```json
// ~/.skill-fog/patterns.json
{
  "patterns": {
    "a3f2b1c4e5d6": {
      "canonical": "FILE에서 NUM번째 줄 오류 어떻게 고쳐",
      "count": 5,
      "sessions": ["session_abc", "session_def", "session_ghi"],
      "examples": [
        "index.ts에서 23번째 줄 오류 어떻게 고쳐",
        "App.tsx에서 145번째 줄 오류 어떻게 고쳐",
        "utils.js에서 67번째 줄 오류 어떻게 고쳐"
      ],
      "first_seen": "2024-01-15T10:00:00Z",
      "last_seen": "2024-01-20T15:30:00Z",
      "status": "proposed"
    }
  }
}
```

### 임계값 / Thresholds

| 조건 | 값 |
|------|-----|
| 최소 발생 횟수 | 3회 |
| 최소 발생 세션 수 | 2개 |
| 최소 메시지 길이 | 20자 |

---

## 프라이버시 / Privacy

- **모든 데이터는 로컬 저장** — 외부 전송 없음
- API 키, 이메일, 토큰 자동 마스킹
- `~/.skill-fog/` 전체가 분석 데이터 저장소

All pattern data is stored locally at `~/.skill-fog/`. No data is sent externally. Secrets are masked automatically.

---

## 파일 구조 / File Structure

```
~/.skill-fog/
├── patterns.json       # 수집된 패턴 DB
├── pending/            # 검토 대기 패턴
│   └── {id}.json
├── logs/               # 세션 처리 로그
│   └── 2024-01-20.log
└── hooks/
    └── stop.sh         # Claude Code Stop 훅

~/.claude/
├── settings.json       # Stop 훅 등록됨
└── skills/
    └── skill-fog/
        └── SKILL.md    # 스킬 정의
```

---

## 제거 / Uninstall

```bash
bash $(dirname $(readlink -f $(which skill-fog)))/../uninstall.sh
```

또는 git 클론한 경우:

```bash
bash /path/to/skill-fog/uninstall.sh
```

---

## 기여 / Contributing

PR과 이슈 환영합니다!

1. Fork the repository
2. Create your branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -m 'feat: add my feature'`
4. Push: `git push origin feature/my-feature`
5. Open a Pull Request

---

## 라이선스 / License

MIT © YOUR_USERNAME
