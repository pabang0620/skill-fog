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

# .messages[]? | select(.role=="user") | .content
if 'messages' in filter_str and 'user' in filter_str:
    results = []
    for m in data.get('messages', []):
        if isinstance(m, dict) and m.get('role') == 'user':
            content = m.get('content', '')
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get('type') == 'text':
                        results.append(item.get('text', ''))
            elif isinstance(content, str):
                results.append(content)
    print('\n'.join(results))

# .session_id // empty
elif 'session_id' in filter_str:
    print(data.get('session_id', ''))

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
# 사용자 메시지 추출
# ─────────────────────────────────────────────
MESSAGES=$(jq_query '.messages[]? | select(.role=="user") | .content')

if [ -z "$MESSAGES" ]; then
  log "INFO: No user messages found in payload"
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
    -e 's/secret[=: ]+[a-zA-Z0-9_-]{8,}/secret=[REDACTED]/gi'
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

  # 기존 패턴 존재 여부 확인
  local existing
  existing=$(jq -r --arg id "$pattern_id" '.patterns[$id] // empty' "$PATTERNS_FILE" 2>/dev/null || echo "")

  if [ -n "$existing" ]; then
    # 이미 이 세션에서 기록됐으면 스킵
    local already
    already=$(jq -r --arg id "$pattern_id" --arg sid "$SESSION_ID" \
      '.patterns[$id].sessions | index($sid) // -1' "$PATTERNS_FILE" 2>/dev/null || echo "-1")

    if [ "$already" != "-1" ]; then
      return
    fi

    # 세션 추가 및 카운트 업데이트
    jq --arg id "$pattern_id" --arg sid "$SESSION_ID" \
      --arg now "$now" --arg ex "$masked_msg" \
      '.patterns[$id].sessions += [$sid] |
       .patterns[$id].count += 1 |
       .patterns[$id].last_seen = $now |
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
}

# ─────────────────────────────────────────────
# python3 기반 패턴 업데이트 함수 (fallback)
# ─────────────────────────────────────────────
update_pattern_python() {
  local pattern_id="$1"
  local canonical="$2"
  local masked_msg="$3"
  local session_id="$SESSION_ID"
  local patterns_file="$PATTERNS_FILE"

  python3 - <<PYEOF
import json, sys, os
import datetime as _dt

pattern_id = '$pattern_id'
canonical = '$canonical'
masked_msg = '''$masked_msg'''
session_id = '$session_id'
patterns_file = '$patterns_file'
now = _dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

try:
    with open(patterns_file, 'r') as f:
        data = json.load(f)
except:
    data = {'patterns': {}}

patterns = data.setdefault('patterns', {})

if pattern_id in patterns:
    p = patterns[pattern_id]
    # 이미 이 세션 기록됐으면 스킵
    if session_id in p.get('sessions', []):
        sys.exit(0)
    p['sessions'].append(session_id)
    p['count'] = p.get('count', 0) + 1
    p['last_seen'] = now
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
    if [ ! -f "$pending_file" ]; then
      jq --arg id "$pattern_id" '.patterns[$id]' "$PATTERNS_FILE" > "$pending_file" 2>/dev/null
      # status → proposed
      jq --arg id "$pattern_id" '.patterns[$id].status = "proposed"' \
        "$PATTERNS_FILE" > "${PATTERNS_FILE}.tmp" 2>/dev/null \
        && mv "${PATTERNS_FILE}.tmp" "$PATTERNS_FILE"
      log "INFO: Pattern $pattern_id promoted to pending (count=$count, sessions=$session_count)"
    fi
  fi
}

# ─────────────────────────────────────────────
# 임계값 확인 및 pending 생성 (python3)
# ─────────────────────────────────────────────
check_threshold_python() {
  local pattern_id="$1"
  local patterns_file="$PATTERNS_FILE"
  local pending_dir="$PENDING_DIR"

  python3 - <<PYEOF
import json, sys, os
import datetime as _dt

pattern_id = '$pattern_id'
patterns_file = '$patterns_file'
pending_dir = '$pending_dir'
now = _dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

try:
    with open(patterns_file, 'r') as f:
        data = json.load(f)
except:
    sys.exit(0)

p = data.get('patterns', {}).get(pattern_id)
if not p:
    sys.exit(0)

count = p.get('count', 0)
session_count = len(p.get('sessions', []))
status = p.get('status', '')

if count >= 3 and session_count >= 2 and status == 'active':
    pending_file = os.path.join(pending_dir, pattern_id + '.json')
    if not os.path.exists(pending_file):
        with open(pending_file, 'w') as f:
            json.dump(p, f, indent=2, ensure_ascii=False)
            f.write('\n')
        p['status'] = 'proposed'
        tmp_file = patterns_file + '.tmp'
        with open(tmp_file, 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write('\n')
        os.replace(tmp_file, patterns_file)
PYEOF
}

# ─────────────────────────────────────────────
# 메시지 정규화 함수
# ─────────────────────────────────────────────
normalize_message() {
  local msg="$1"
  echo "$msg" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[a-zA-Z0-9_\/-]+\.(ts|tsx|js|jsx|py|md|json|sh|yaml|yml|env|toml)/FILE/g' \
    | sed -E 's/[0-9]+/NUM/g' \
    | sed -E 's/https?:\/\/[^ ]+/URL/g' \
    | sed -E 's/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/UUID/g' \
    | tr -s ' \t\n' ' ' \
    | sed -E 's/^ +| +$//g' \
    | cut -c1-120
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
      pattern_id=$(echo "$canonical" | md5sum | head -c 12)
    elif command -v md5 &>/dev/null; then
      pattern_id=$(echo "$canonical" | md5 | head -c 12)
    else
      pattern_id=$(echo "$canonical" | shasum | head -c 12)
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

exit 0
