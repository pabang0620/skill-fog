#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# skill-fog: SessionStart hook
# Claude Code 세션 시작 시 자동 실행 — pending 패턴을 Claude 컨텍스트에 주입
# stdout은 Claude Code에 의해 첫 프롬프트 전 컨텍스트로 주입됨 (SessionStart 훅 특성)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PENDING_DIR="$HOME/.skill-fog/pending"

# stdin payload에서 source 필드 추출
PAYLOAD=$(cat)

SOURCE=""
if command -v python3 &>/dev/null; then
  SOURCE=$(SF_PAYLOAD="$PAYLOAD" python3 - <<'PYEOF'
import json, os, sys
try:
    data = json.loads(os.environ.get('SF_PAYLOAD', '{}'))
    print(data.get('source', ''))
except Exception:
    print('')
PYEOF
)
fi

# startup / resume 이외에는 조용히 종료
# clear: 세션 중간 /clear 재시작 — 현재 작업 맥락에서 pending 제안은 노이즈가 됨
# compact: 컨텍스트 압축 후 — 동일한 이유로 제외
# (compact 후에도 제안을 원하면 아래 패턴에 compact를 추가)
case "$SOURCE" in
  startup|resume) ;;
  *) exit 0 ;;
esac

# pending 디렉토리 없거나 파일 없으면 조용히 종료
if [ ! -d "$PENDING_DIR" ]; then
  exit 0
fi

# pending JSON 파일이 하나라도 있는지 확인
has_pending=0
for f in "$PENDING_DIR"/*.json; do
  [ -e "$f" ] && has_pending=1 && break
done

if [ "$has_pending" -eq 0 ]; then
  exit 0
fi

# pending 패턴 파싱 후 stdout 출력 (Claude context에 주입됨)
# 최대 5개, count 내림차순
# 제안 후 즉시 pending 파일 삭제 + patterns.json snoozed 전환 (재제안 방지)
SF_PENDING_DIR="$PENDING_DIR" SF_PATTERNS_FILE="$HOME/.skill-fog/patterns.json" python3 - <<'PYEOF'
import json, os, sys

pending_dir = os.environ['SF_PENDING_DIR']
patterns_file = os.environ['SF_PATTERNS_FILE']
items = []

for fname in sorted(os.listdir(pending_dir)):
    if not fname.endswith('.json'):
        continue
    fpath = os.path.join(pending_dir, fname)
    try:
        with open(fpath, encoding='utf-8') as f:
            data = json.load(f)
    except Exception:
        continue
    if data.get('status') in ('rejected', 'accepted'):
        continue
    pid = os.path.splitext(fname)[0]
    items.append((fpath, pid, data))

if not items:
    sys.exit(0)

items.sort(key=lambda x: x[2].get('count', 0), reverse=True)
total = len(items)
items = items[:5]

print(f'[skill-fog] You have {total} repeated pattern(s) pending review.')
print()
for i, (fpath, pid, item) in enumerate(items, 1):
    canonical = item.get('canonical', '').strip()
    count = item.get('count', 0)
    sessions = len(item.get('sessions', []))
    examples = item.get('examples', [])
    example = examples[0][:80].strip() if examples else ''

    print(f'{i}. "{canonical}" — {count}x, {sessions} session(s)')
    if example and example.lower() != canonical.lower():
        print(f'   example: {example}')

print()
print('Run STEP A: for each pattern, propose creating a skill / command / agent to the user.')
print('Manual invocation is also available via /skill-fog.')
print('(Respond in the same language the user is using.)')

# ── 제안 후 정리: pending 삭제 + snoozed 전환 (무시해도 다음 세션 재제안 없음) ──
proposed_pids = [pid for _, pid, _ in items]

for fpath, pid, _ in items:
    try:
        os.remove(fpath)
    except Exception:
        pass

if proposed_pids and os.path.exists(patterns_file):
    try:
        with open(patterns_file, 'r', encoding='utf-8') as f:
            pdata = json.load(f)
        changed = False
        for pid in proposed_pids:
            p = pdata.get('patterns', {}).get(pid)
            if p and p.get('status') == 'active':
                p['status'] = 'snoozed'
                changed = True
        if changed:
            tmp = patterns_file + '.tmp'
            with open(tmp, 'w', encoding='utf-8') as f:
                json.dump(pdata, f, indent=2, ensure_ascii=False)
                f.write('\n')
            os.replace(tmp, patterns_file)
    except Exception:
        pass
PYEOF
