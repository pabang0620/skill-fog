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
CURSOR_DIR="$HOME/.skill-fog/transcript-cursors"

mkdir -p "$LOG_DIR" 2>/dev/null || true

# ─────────────────────────────────────────────
# 로그 함수
# ─────────────────────────────────────────────
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOG_FILE" 2>/dev/null || true
}

payload_summary() {
  SF_PAYLOAD="$PAYLOAD" python3 - <<'PYEOF'
import json, os

try:
    data = json.loads(os.environ.get('SF_PAYLOAD', '{}'))
except Exception:
    print('keys=[] session= hook_event=')
    raise SystemExit(0)

if not isinstance(data, dict):
    print('keys=[] session= hook_event=')
    raise SystemExit(0)

keys = sorted(str(k) for k in data.keys())
session = data.get('session_id') or data.get('sessionId') or ''
hook_event = data.get('hook_event_name') or data.get('hookEventName') or data.get('event') or ''
print(f"keys={keys} session={session} hook_event={hook_event}")
PYEOF
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
elif command -v python3 &>/dev/null; then
  if ! SF_PAYLOAD="$PAYLOAD" python3 - <<'PYEOF' >/dev/null 2>&1
import json, os
json.loads(os.environ.get('SF_PAYLOAD', ''))
PYEOF
  then
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

if ! command -v python3 &>/dev/null; then
  log "ERROR: python3 is required for transcript parsing"
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

# .session_id // .sessionId // empty
if 'session_id' in filter_str or 'sessionId' in filter_str:
    print(data.get('session_id') or data.get('sessionId') or '')

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
SESSION_ID=$(jq_query '.session_id // .sessionId // empty')
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
  log "INFO: No transcript_path in payload ($(payload_summary))"
  exit 0
fi

if [ ! -f "$TRANSCRIPT_PATH" ]; then
  log "WARN: transcript_path does not exist: $TRANSCRIPT_PATH"
  exit 0
fi

log "INFO: Reading transcript: $TRANSCRIPT_PATH"

# ─────────────────────────────────────────────
# Transcript cursor state
# ─────────────────────────────────────────────
mkdir -p "$CURSOR_DIR"

TRANSCRIPT_CURSOR_KEY=$(SF_SESSION_ID="$SESSION_ID" SF_TRANSCRIPT_PATH="$TRANSCRIPT_PATH" python3 - <<'PYEOF'
import hashlib, os

session_id = os.environ.get('SF_SESSION_ID', '')
transcript_path = os.environ.get('SF_TRANSCRIPT_PATH', '')
print(hashlib.sha256(f'{session_id}\0{transcript_path}'.encode('utf-8', errors='replace')).hexdigest()[:32])
PYEOF
)
TRANSCRIPT_CURSOR_FILE="$CURSOR_DIR/${TRANSCRIPT_CURSOR_KEY}.json"
TRANSCRIPT_CURSOR_LOCK_DIR="$CURSOR_DIR/${TRANSCRIPT_CURSOR_KEY}.lockdir"
TRANSCRIPT_CURSOR_LOCKED=0
TRANSCRIPT_CURSOR_NEXT_OFFSET=0

release_transcript_cursor_lock() {
  if [ "$TRANSCRIPT_CURSOR_LOCKED" -eq 1 ]; then
    rmdir "$TRANSCRIPT_CURSOR_LOCK_DIR" 2>/dev/null || true
    TRANSCRIPT_CURSOR_LOCKED=0
  fi
}

acquire_transcript_cursor_lock() {
  local attempts=0
  while ! mkdir "$TRANSCRIPT_CURSOR_LOCK_DIR" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 200 ]; then
      log "WARN: Could not acquire transcript cursor lock for $TRANSCRIPT_PATH"
      return 1
    fi
    sleep 0.05
  done
  TRANSCRIPT_CURSOR_LOCKED=1
  trap release_transcript_cursor_lock EXIT
}

write_transcript_cursor() {
  local offset="$1"

  SF_CURSOR_FILE="$TRANSCRIPT_CURSOR_FILE" \
  SF_SESSION_ID="$SESSION_ID" \
  SF_TRANSCRIPT_PATH="$TRANSCRIPT_PATH" \
  SF_OFFSET="$offset" \
  python3 - <<'PYEOF'
import datetime as _dt
import json
import os

cursor_file = os.environ['SF_CURSOR_FILE']
offset = int(os.environ.get('SF_OFFSET') or 0)
data = {
    'session_id': os.environ.get('SF_SESSION_ID', ''),
    'transcript_path': os.environ.get('SF_TRANSCRIPT_PATH', ''),
    'byte_offset': offset,
    'updated_at': _dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
}
tmp_file = cursor_file + '.tmp'
with open(tmp_file, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
os.replace(tmp_file, cursor_file)
PYEOF
}

if ! acquire_transcript_cursor_lock; then
  exit 0
fi

# ─────────────────────────────────────────────
# JSONL transcript에서 사용자 메시지 추출
# legacy top-level role/content와 Claude JSONL nested message.content를 지원한다.
# content 배열은 text item만 수집하고 tool_result payload는 제외한다.
# 각 메시지는 base64 한 줄로 출력해 멀티라인 메시지 경계를 보존한다.
# ─────────────────────────────────────────────
MESSAGES_OUTPUT=$(SF_TRANSCRIPT_PATH="$TRANSCRIPT_PATH" SF_CURSOR_FILE="$TRANSCRIPT_CURSOR_FILE" python3 - <<'PYEOF'
import base64, os, json, sys

transcript_path = os.environ.get('SF_TRANSCRIPT_PATH', '')
cursor_file = os.environ.get('SF_CURSOR_FILE', '')
results = []
offset = 0
next_offset = 0

def clean_text(text):
    return text.encode('utf-8', errors='replace').decode('utf-8')

def text_parts(content):
    if isinstance(content, str):
        if content:
            yield clean_text(content)
    elif isinstance(content, list):
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get('type') != 'text':
                continue
            text = item.get('text', '')
            if isinstance(text, str) and text:
                yield clean_text(text)

try:
    try:
        with open(cursor_file, 'r', encoding='utf-8') as cursor_f:
            cursor = json.load(cursor_f)
            offset = int(cursor.get('byte_offset') or 0)
    except Exception:
        offset = 0

    file_size = os.path.getsize(transcript_path)
    if offset < 0 or offset > file_size:
        offset = 0

    with open(transcript_path, 'rb') as f:
        f.seek(offset)
        next_offset = f.tell()

        for raw_line in f:
            next_offset = f.tell()
            try:
                line = raw_line.decode('utf-8', errors='replace').strip()
            except Exception:
                continue
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get('role') == 'user':
                results.extend(text_parts(obj.get('content', '')))
            else:
                message = obj.get('message')
                if (
                    obj.get('type') == 'user'
                    and isinstance(message, dict)
                    and message.get('role') == 'user'
                ):
                    results.extend(text_parts(message.get('content', '')))

            if len(results) >= 50:
                break
except Exception as e:
    import sys as _sys
    _sys.stderr.write(f'[skill-fog] transcript read error: {e}\n')

print(f'__SF_NEXT_OFFSET__={next_offset}')
for message in results:
    print(base64.b64encode(message.encode('utf-8')).decode('ascii'))
PYEOF
)

TRANSCRIPT_CURSOR_NEXT_OFFSET=$(printf '%s\n' "$MESSAGES_OUTPUT" | sed -n 's/^__SF_NEXT_OFFSET__=//p' | head -n 1)
MESSAGES_B64=$(printf '%s\n' "$MESSAGES_OUTPUT" | sed '/^__SF_NEXT_OFFSET__=/d')

if [ -z "$TRANSCRIPT_CURSOR_NEXT_OFFSET" ]; then
  log "WARN: Could not determine transcript cursor offset for $TRANSCRIPT_PATH"
  TRANSCRIPT_CURSOR_NEXT_OFFSET=0
fi

if [ -z "$MESSAGES_B64" ]; then
  write_transcript_cursor "$TRANSCRIPT_CURSOR_NEXT_OFFSET"
  release_transcript_cursor_lock
  log "INFO: No new user messages found in transcript"
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

def clean_text(value):
    if not isinstance(value, str):
        return value
    return value.encode('utf-8', errors='replace').decode('utf-8')

def clean_json(value):
    if isinstance(value, str):
        return clean_text(value)
    if isinstance(value, list):
        return [clean_json(item) for item in value]
    if isinstance(value, dict):
        return {clean_json(k): clean_json(v) for k, v in value.items()}
    return value

pattern_id = os.environ['SF_PATTERN_ID']
canonical = clean_text(os.environ['SF_CANONICAL'])
masked_msg = clean_text(os.environ['SF_MASKED_MSG'])
session_id = clean_text(os.environ['SF_SESSION_ID'])
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
            json.dump(clean_json(data), f, indent=2, ensure_ascii=False)
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
  check_threshold_python "$pattern_id"
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

def clean_json(value):
    if isinstance(value, str):
        return value.encode('utf-8', errors='replace').decode('utf-8')
    if isinstance(value, list):
        return [clean_json(item) for item in value]
    if isinstance(value, dict):
        return {clean_json(k): clean_json(v) for k, v in value.items()}
    return value

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
        status = p.get('status', 'active')

        if count >= 3 and session_count >= 2 and status not in ('accepted', 'rejected'):
            pending_file = os.path.join(pending_dir, pattern_id + '.json')
            existing_pending = {}
            if os.path.exists(pending_file):
                try:
                    with open(pending_file, 'r') as f:
                        existing_pending = json.load(f)
                except Exception:
                    existing_pending = {}

            pending_data = {
                'pid': pattern_id,
                'canonical': clean_json(p.get('canonical', '')),
                'count': p.get('count', 0),
                'sessions': clean_json(p.get('sessions', [])),
                'examples': clean_json(p.get('examples', [])),
                'first_seen': clean_json(p.get('first_seen', '')),
                'last_seen': clean_json(p.get('last_seen', '')),
                'status': 'active',
            }
            if existing_pending.get('snoozed_at'):
                pending_data['snoozed_at'] = existing_pending['snoozed_at']

            p['status'] = 'active'

            tmp_patterns = patterns_file + '.tmp'
            with open(tmp_patterns, 'w') as f:
                json.dump(clean_json(data), f, indent=2, ensure_ascii=False)
                f.write('\n')

            tmp_pending = pending_file + '.tmp'
            with open(tmp_pending, 'w') as f:
                json.dump(pending_data, f, indent=2, ensure_ascii=False)
                f.write('\n')

            os.replace(tmp_pending, pending_file)
            os.replace(tmp_patterns, patterns_file)
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
    | sed -E 's/[a-zA-Z0-9_\/-]+\.(tsx|ts|jsx|js|py|md|json|sh|yaml|yml|env|toml)/FILE/g' \
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

  while IFS= read -r encoded_msg; do
    [ -z "$encoded_msg" ] && continue
    local msg
    msg=$(SF_MESSAGE_B64="$encoded_msg" python3 - <<'PYEOF'
import base64, os
try:
    print(base64.b64decode(os.environ.get('SF_MESSAGE_B64', ''), validate=True).decode('utf-8'), end='')
except Exception:
    print('', end='')
PYEOF
)
    [ -z "$msg" ] && continue

    # 시크릿 마스킹
    local masked
    masked=$(printf '%s' "$msg" | mask_secrets)

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

  done <<< "$MESSAGES_B64"

  log "INFO: Processed $processed messages for session $SESSION_ID"
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
process_messages
write_transcript_cursor "$TRANSCRIPT_CURSOR_NEXT_OFFSET"
release_transcript_cursor_lock

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
