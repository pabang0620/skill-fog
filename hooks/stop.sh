#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# skill-fog: Stop hook
# Claude Code 세션 종료 시 자동 실행 — 사용자 메시지 패턴 수집 및 분석
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PATTERNS_FILE="$HOME/.skill-fog/patterns.json"
PENDING_DIR="$HOME/.skill-fog/pending"
LOG_DIR="$HOME/.skill-fog/logs"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"

# ─────────────────────────────────────────────
# 로그 함수
# ─────────────────────────────────────────────
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# stdin에서 페이로드 읽기 (Claude Code Stop 훅)
# ─────────────────────────────────────────────
PAYLOAD=$(cat)

if [ -z "$PAYLOAD" ]; then
  log "WARN: Empty payload received"
  exit 0
fi

# JSON 유효성 검사
if command -v jq &>/dev/null; then
  if ! echo "$PAYLOAD" | jq empty 2>/dev/null; then
    log "ERROR: Invalid JSON payload (length=${#PAYLOAD})"
    exit 0
  fi
fi

# ─────────────────────────────────────────────
# jq 사용 가능 여부 확인 (python3 fallback)
# ─────────────────────────────────────────────
JQ_CMD=""
PYTHON_CMD=""

if command -v jq &>/dev/null; then
  JQ_CMD="jq"
elif command -v python3 &>/dev/null; then
  PYTHON_CMD="python3"
else
  log "ERROR: Neither jq nor python3 available"
  exit 0
fi

# flock 없으면 python3 경로 강제 (macOS 호환성)
# flock은 Linux(util-linux) 전용 — macOS는 python3의 fcntl.flock 사용
if [ -n "$JQ_CMD" ] && ! command -v flock &>/dev/null; then
  log "INFO: flock not available, using python3 for atomic operations"
  JQ_CMD=""
fi

# JSON 쿼리 래퍼 함수 (jq 없으면 python3 — 환경변수로 전달해 따옴표 문제 회피)
jq_query() {
  local filter="$1"
  local input="${2:-$PAYLOAD}"
  if [ -n "$JQ_CMD" ]; then
    echo "$input" | jq -r "$filter" 2>/dev/null || echo ""
  else
    SF_FILTER="$filter" SF_INPUT="$input" python3 - <<'PYEOF'
import os, json, sys

filter_str = os.environ.get('SF_FILTER', '')
input_str = os.environ.get('SF_INPUT', '')

try:
    data = json.loads(input_str)
except Exception:
    print('')
    sys.exit(0)

# .session_id // empty
if 'session_id' in filter_str:
    print(data.get('session_id', ''))

# .transcript_path // empty
elif 'transcript_path' in filter_str:
    print(data.get('transcript_path', ''))

else:
    print('')
PYEOF
  fi
}

# ─────────────────────────────────────────────
# 세션 ID 추출
# ─────────────────────────────────────────────
SESSION_ID=$(jq_query '.session_id // empty')
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="session_$(date +%s | md5sum 2>/dev/null | head -c 8 || date +%s | shasum | head -c 8)"
fi

log "INFO: Processing session $SESSION_ID"

# ─────────────────────────────────────────────
# transcript_path 추출 (Stop hook payload 형식)
# Claude Code Stop hook은 messages 배열이 아닌 transcript_path를 제공
# ─────────────────────────────────────────────
TRANSCRIPT_PATH=""
if [ -n "$JQ_CMD" ]; then
  TRANSCRIPT_PATH=$(echo "$PAYLOAD" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
else
  TRANSCRIPT_PATH=$(SF_PAYLOAD="$PAYLOAD" python3 - <<'PYEOF'
import os, json, sys
try:
    d = json.loads(os.environ.get('SF_PAYLOAD', '{}'))
    print(d.get('transcript_path', ''))
except Exception:
    print('')
PYEOF
)
fi

if [ -z "$TRANSCRIPT_PATH" ]; then
  log "INFO: No transcript_path in payload (session may have no transcript)"
  exit 0
fi

if [ ! -f "$TRANSCRIPT_PATH" ]; then
  log "WARN: transcript_path does not exist: $TRANSCRIPT_PATH"
  exit 0
fi

log "INFO: Reading transcript: $TRANSCRIPT_PATH"

# ─────────────────────────────────────────────
# JSONL transcript에서 사용자 메시지 추출
# 형식: {"role":"user","content":"..."} 또는 content가 배열인 경우
# ─────────────────────────────────────────────
MESSAGES=$(SF_TRANSCRIPT_PATH="$TRANSCRIPT_PATH" python3 - <<'PYEOF'
import os, json, sys

transcript_path = os.environ.get('SF_TRANSCRIPT_PATH', '')
results = []

try:
    with open(transcript_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get('role') == 'user':
                content = obj.get('content', '')
                if isinstance(content, str):
                    results.append(content)
                elif isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict) and item.get('type') == 'text':
                            text = item.get('text', '')
                            if text:
                                results.append(text)
except Exception as e:
    import sys as _sys
    _sys.stderr.write(f'[skill-fog] transcript read error: {e}\n')

print('\n'.join(results))
PYEOF
)

if [ -z "$MESSAGES" ]; then
  log "INFO: No user messages found in transcript"
  exit 0
fi

# ─────────────────────────────────────────────
# 시크릿 마스킹 함수
# ─────────────────────────────────────────────
mask_secrets() {
  sed -E \
    -e 's/sk-ant-[a-zA-Z0-9_-]+/[REDACTED]/g' \
    -e 's/sk-proj-[a-zA-Z0-9_-]+/[REDACTED]/g' \
    -e 's/ghp_[a-zA-Z0-9]+/[REDACTED]/g' \
    -e 's/AKIA[A-Z0-9]{16}/[REDACTED]/g' \
    -e 's/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/[EMAIL]/g' \
    -e 's/password[=: ]+[^ ]*/password=[REDACTED]/gi' \
    -e 's/token[=: ]+[a-zA-Z0-9_-]{10,}/token=[REDACTED]/gi' \
    -e 's/secret[=: ]+[a-zA-Z0-9_-]{8,}/secret=[REDACTED]/gi' \
    -e 's|postgresql://[^:]*:[^@]*@|postgresql://***:***@|g' \
    -e 's|mysql://[^:]*:[^@]*@|mysql://***:***@|g' \
    -e 's|mongodb://[^:]*:[^@]*@|mongodb://***:***@|g' \
    -e 's|redis://[^:]*:[^@]*@|redis://***:***@|g' \
    -e 's|-----BEGIN [A-Z ]* PRIVATE KEY-----|[PRIVATE_KEY_REDACTED]|g'
}

# ─────────────────────────────────────────────
# patterns.json 초기화 (없으면)
# ─────────────────────────────────────────────
mkdir -p "$PENDING_DIR" "$LOG_DIR"

if [ ! -f "$PATTERNS_FILE" ]; then
  echo '{"patterns":{}}' > "$PATTERNS_FILE"
fi

# ─────────────────────────────────────────────
# jq 기반 패턴 업데이트 함수
# ─────────────────────────────────────────────
update_pattern_jq() {
  local pattern_id="$1"
  local canonical="$2"
  local masked_msg="$3"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local tmp_file="${PATTERNS_FILE}.tmp"

  (
    flock -x 200

    # 기존 패턴 존재 여부 확인
    local existing
    existing=$(jq -r --arg id "$pattern_id" '.patterns[$id] // empty' "$PATTERNS_FILE" 2>/dev/null || echo "")

    if [ -n "$existing" ]; then
      # count는 매 메시지마다 증가, sessions는 세션당 1회만 추가 (dedup)
      jq --arg id "$pattern_id" --arg sid "$SESSION_ID" \
        --arg now "$now" --arg ex "$masked_msg" \
        '.patterns[$id].count += 1 |
         .patterns[$id].last_seen = $now |
         if (.patterns[$id].sessions | index($sid)) == null then
           .patterns[$id].sessions += [$sid]
         else . end |
         if ((.patterns[$id].examples | length) < 3) then
           .patterns[$id].examples += [$ex]
         else . end' \
        "$PATTERNS_FILE" > "$tmp_file" && mv "$tmp_file" "$PATTERNS_FILE"
    else
      # 신규 패턴 생성
      jq --arg id "$pattern_id" --arg sid "$SESSION_ID" \
        --arg canonical "$canonical" --arg ex "$masked_msg" \
        --arg now "$now" \
        '.patterns[$id] = {
          canonical: $canonical,
          count: 1,
          sessions: [$sid],
          examples: [$ex],
          first_seen: $now,
          last_seen: $now,
          status: "active"
        }' \
        "$PATTERNS_FILE" > "$tmp_file" && mv "$tmp_file" "$PATTERNS_FILE"
    fi

  ) 200>"${PATTERNS_FILE}.lock"
}

# ─────────────────────────────────────────────
# python3 기반 패턴 업데이트 함수 (fallback)
# ─────────────────────────────────────────────
update_pattern_python() {
  local pattern_id="$1"
  local canonical="$2"
  local masked_msg="$3"

  SF_PATTERN_ID="$pattern_id" \
  SF_CANONICAL="$canonical" \
  SF_MASKED_MSG="$masked_msg" \
  SF_SESSION_ID="$SESSION_ID" \
  SF_PATTERNS_FILE="$PATTERNS_FILE" \
  python3 - <<'PYEOF'
import os, json, sys, fcntl
import datetime as _dt

pattern_id = os.environ['SF_PATTERN_ID']
canonical = os.environ['SF_CANONICAL']
masked_msg = os.environ['SF_MASKED_MSG']
session_id = os.environ['SF_SESSION_ID']
patterns_file = os.environ['SF_PATTERNS_FILE']
now = _dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

lock_file = patterns_file + '.lock'
with open(lock_file, 'w') as lock_f:
    fcntl.flock(lock_f, fcntl.LOCK_EX)
    try:
        try:
            with open(patterns_file, 'r') as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            import sys as _sys
            _sys.stderr.write(f'[skill-fog] JSON parse error: {e}\n')
            print('')
            sys.exit(0)
        except Exception:
            data = {'patterns': {}}

        patterns = data.setdefault('patterns', {})

        if pattern_id in patterns:
            p = patterns[pattern_id]
            # count는 매 메시지마다 증가, sessions는 dedup (세션당 1회만)
            p['count'] = p.get('count', 0) + 1
            p['last_seen'] = now
            if session_id not in p.get('sessions', []):
                p.setdefault('sessions', []).append(session_id)
            if len(p.get('examples', [])) < 3:
                p.setdefault('examples', []).append(masked_msg)
        else:
            patterns[pattern_id] = {
                'canonical': canonical,
                'count': 1,
                'sessions': [session_id],
                'examples': [masked_msg],
                'first_seen': now,
                'last_seen': now,
                'status': 'active'
            }

        tmp_file = patterns_file + '.tmp'
        with open(tmp_file, 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write('\n')
        os.replace(tmp_file, patterns_file)
    finally:
        fcntl.flock(lock_f, fcntl.LOCK_UN)
PYEOF
}

# ─────────────────────────────────────────────
# 임계값 확인 및 pending 생성 (jq)
# ─────────────────────────────────────────────
check_threshold_jq() {
  local pattern_id="$1"

  local count session_count status
  count=$(jq -r --arg id "$pattern_id" '.patterns[$id].count' "$PATTERNS_FILE" 2>/dev/null || echo "0")
  session_count=$(jq -r --arg id "$pattern_id" '.patterns[$id].sessions | length' "$PATTERNS_FILE" 2>/dev/null || echo "0")
  status=$(jq -r --arg id "$pattern_id" '.patterns[$id].status' "$PATTERNS_FILE" 2>/dev/null || echo "")

  if [ "${count:-0}" -ge 3 ] && [ "${session_count:-0}" -ge 2 ] && [ "$status" = "active" ]; then
    local pending_file="$PENDING_DIR/${pattern_id}.json"
    (
      flock -x 200

      # status → proposed 먼저 업데이트 (atomic)
      jq --arg id "$pattern_id" '.patterns[$id].status = "proposed"' \
        "$PATTERNS_FILE" > "${PATTERNS_FILE}.tmp" 2>/dev/null \
        && mv "${PATTERNS_FILE}.tmp" "$PATTERNS_FILE" || { log "ERROR: Failed to update status for $pattern_id"; }

      # pending 파일 생성 (noclobber — 이미 존재하면 건너뜀, status는 proposed 유지)
      set -C
      if jq --arg id "$pattern_id" '.patterns[$id]' "$PATTERNS_FILE" > "$pending_file" 2>/dev/null; then
        set +C
        log "INFO: Pattern $pattern_id promoted to pending (count=$count, sessions=$session_count)"
      else
        set +C
      fi

    ) 200>"${PATTERNS_FILE}.lock"
  fi
}

# ─────────────────────────────────────────────
# 임계값 확인 및 pending 생성 (python3)
# ─────────────────────────────────────────────
check_threshold_python() {
  local pattern_id="$1"

  SF_PATTERN_ID="$pattern_id" \
  SF_PATTERNS_FILE="$PATTERNS_FILE" \
  SF_PENDING_DIR="$PENDING_DIR" \
  python3 - <<'PYEOF'
import os, json, sys, fcntl
import datetime as _dt

pattern_id = os.environ['SF_PATTERN_ID']
patterns_file = os.environ['SF_PATTERNS_FILE']
pending_dir = os.environ['SF_PENDING_DIR']
now = _dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

lock_file = patterns_file + '.lock'
with open(lock_file, 'w') as lock_f:
    fcntl.flock(lock_f, fcntl.LOCK_EX)
    try:
        try:
            with open(patterns_file, 'r') as f:
                data = json.load(f)
        except Exception:
            sys.exit(0)

        p = data.get('patterns', {}).get(pattern_id)
        if not p:
            sys.exit(0)

        count = p.get('count', 0)
        session_count = len(p.get('sessions', []))
        status = p.get('status', '')

        if count >= 3 and session_count >= 2 and status == 'active':
            pending_file = os.path.join(pending_dir, pattern_id + '.json')
            # status → proposed 먼저 업데이트 (atomic)
            p['status'] = 'proposed'
            tmp_file = patterns_file + '.tmp'
            with open(tmp_file, 'w') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
                f.write('\n')
            os.replace(tmp_file, patterns_file)
            # pending 파일 생성 (O_EXCL — 이미 존재하면 건너뜀, status는 proposed 유지)
            try:
                fd = os.open(pending_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
                with os.fdopen(fd, 'w') as f:
                    json.dump(p, f, indent=2, ensure_ascii=False)
                    f.write('\n')
            except FileExistsError:
                pass
    finally:
        fcntl.flock(lock_f, fcntl.LOCK_UN)
PYEOF
}

# ─────────────────────────────────────────────
# 메시지 정규화 함수
# ─────────────────────────────────────────────
normalize_message() {
  local msg="$1"
  echo "$msg" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[a-zA-Z0-9_\/-]+\.(tsx|ts|jsx|json|yaml|js|yml|py|md|sh|env|toml)/FILE/g' \
    | sed -E 's/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/UUID/g' \
    | sed -E 's/https?:\/\/[^ ]+/URL/g' \
    | sed -E 's/[0-9]+/NUM/g' \
    | tr -s ' \t\n' ' ' \
    | sed -E 's/^ +| +$//g' \
    | cut -c1-120
}

# ─────────────────────────────────────────────
# 오래된 패턴 정리 함수 (30일)
# ─────────────────────────────────────────────
cleanup_old_patterns() {
  local cutoff
  cutoff=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
           python3 -c "import datetime; print((datetime.datetime.utcnow() - datetime.timedelta(days=30)).isoformat() + 'Z')" 2>/dev/null || echo "")

  if [ -z "$cutoff" ]; then
    return
  fi

  SF_CUTOFF="$cutoff" \
  SF_PATTERNS_FILE="$PATTERNS_FILE" \
  python3 - <<'PYEOF'
import os, json, fcntl

cutoff = os.environ.get('SF_CUTOFF', '')
pf = os.environ.get('SF_PATTERNS_FILE', '')

if not cutoff or not pf:
    exit(0)

lock_file = pf + '.lock'
try:
    with open(lock_file, 'w') as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        try:
            with open(pf) as f:
                data = json.load(f)
            before = len(data['patterns'])
            data['patterns'] = {
                k: v for k, v in data['patterns'].items()
                if v.get('status') not in ('rejected',) and
                   v.get('last_seen', '9999') >= cutoff
            }
            after = len(data['patterns'])
            if before != after:
                with open(pf + '.tmp', 'w') as f:
                    json.dump(data, f, indent=2, ensure_ascii=False)
                    f.write('\n')
                os.replace(pf + '.tmp', pf)
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)
except Exception:
    pass
PYEOF
}

# ─────────────────────────────────────────────
# 각 사용자 메시지 처리
# ─────────────────────────────────────────────
process_messages() {
  local processed=0

  while IFS= read -r msg; do
    [ -z "$msg" ] && continue

    # 시크릿 마스킹
    local masked
    masked=$(echo "$msg" | mask_secrets)

    # 최소 길이 필터: 10자 이상 (한글 등 멀티바이트 문자 고려)
    if [ "${#masked}" -lt 10 ]; then
      continue
    fi

    # 정규화
    local canonical
    canonical=$(normalize_message "$masked")

    if [ -z "$canonical" ]; then
      continue
    fi

    # 패턴 ID 생성 (정규화된 텍스트의 해시)
    local pattern_id
    if command -v md5sum &>/dev/null; then
      pattern_id=$(printf '%s' "$canonical" | md5sum | head -c 12)
    elif command -v md5 &>/dev/null; then
      pattern_id=$(printf '%s' "$canonical" | md5 | head -c 12)
    else
      pattern_id=$(printf '%s' "$canonical" | shasum | head -c 12)
    fi

    log "DEBUG: Processing pattern $pattern_id (len=${#masked})"

    # 패턴 업데이트
    if [ -n "$JQ_CMD" ]; then
      update_pattern_jq "$pattern_id" "$canonical" "$masked"
      check_threshold_jq "$pattern_id"
    else
      update_pattern_python "$pattern_id" "$canonical" "$masked"
      check_threshold_python "$pattern_id"
    fi

    processed=$((processed + 1))

    # 처리 메시지 수 제한 (성능)
    [ "$processed" -ge 50 ] && break

  done <<< "$MESSAGES"

  log "INFO: Processed $processed messages for session $SESSION_ID"
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
process_messages

# 세션 카운트 기반 오래된 패턴 정리 (매 10번째 실행마다)
SESSION_COUNT_FILE="$HOME/.skill-fog/.session_count"
session_count=0
if [ -f "$SESSION_COUNT_FILE" ]; then
  session_count=$(cat "$SESSION_COUNT_FILE" 2>/dev/null || echo "0")
fi
session_count=$((session_count + 1))
echo "$session_count" > "$SESSION_COUNT_FILE"

if [ $((session_count % 10)) -eq 0 ]; then
  cleanup_old_patterns
  log "INFO: Ran cleanup_old_patterns at session count $session_count"
fi

exit 0
