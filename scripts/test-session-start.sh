#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# skill-fog: hooks/session-start.sh regression test
# Exercises the pending-pattern injection + snooze/cleanup logic against an
# isolated temporary HOME. Never touches the real ~/.skill-fog or ~/.claude.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
hook="$repo_dir/hooks/session-start.sh"

if ! command -v python3 &>/dev/null; then
  printf 'test-session-start: python3 is required but was not found\n' >&2
  exit 1
fi

if [ ! -f "$hook" ]; then
  printf 'test-session-start: hook not found at %s\n' "$hook" >&2
  exit 1
fi

failures=0
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-fog-session-start-test.XXXXXX")"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

fail() {
  local scenario="$1"
  local reason="$2"
  printf '[FAIL] %s: %s\n' "$scenario" "$reason" >&2
  failures=$((failures + 1))
}

pass() {
  local scenario="$1"
  printf '[PASS] %s\n' "$scenario"
}

# ── fixture helpers ──────────────────────────────────────────────────────────

# create_pending HOME PID CANONICAL COUNT SESSION_COUNT
create_pending() {
  local home="$1" pid="$2" canonical="$3" count="$4" session_count="$5"
  mkdir -p "$home/.skill-fog/pending"
  python3 - "$home" "$pid" "$canonical" "$count" "$session_count" <<'PYEOF'
import json, os, sys

home, pid, canonical, count, session_count = sys.argv[1:6]
count = int(count)
session_count = int(session_count)

data = {
    "pid": pid,
    "canonical": canonical,
    "count": count,
    "sessions": [f"session-{i}" for i in range(session_count)],
    "examples": [canonical],
    "first_seen": "2026-01-01T00:00:00Z",
    "last_seen": "2026-01-02T00:00:00Z",
    "status": "active",
}
path = os.path.join(home, ".skill-fog", "pending", pid + ".json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
}

# init_patterns_file HOME PID [PID...]
# Builds patterns.json entries from the matching pending fixture files
# (must be called after create_pending for each pid).
init_patterns_file() {
  local home="$1"
  shift
  mkdir -p "$home/.skill-fog"
  python3 - "$home" "$@" <<'PYEOF'
import json, os, sys

home = sys.argv[1]
pids = sys.argv[2:]
patterns = {}
for pid in pids:
    pending_path = os.path.join(home, ".skill-fog", "pending", pid + ".json")
    with open(pending_path, encoding="utf-8") as f:
        pending = json.load(f)
    patterns[pid] = {
        "canonical": pending["canonical"],
        "count": pending["count"],
        "sessions": pending["sessions"],
        "examples": pending["examples"],
        "first_seen": pending["first_seen"],
        "last_seen": pending["last_seen"],
        "status": "active",
    }

path = os.path.join(home, ".skill-fog", "patterns.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump({"patterns": patterns}, f, indent=2, ensure_ascii=False)
PYEOF
}

# pattern_status HOME PID
pattern_status() {
  local home="$1" pid="$2"
  python3 - "$home" "$pid" <<'PYEOF'
import json, os, sys

home, pid = sys.argv[1], sys.argv[2]
path = os.path.join(home, ".skill-fog", "patterns.json")
with open(path, encoding="utf-8") as f:
    data = json.load(f)
print(data.get("patterns", {}).get(pid, {}).get("status", ""))
PYEOF
}

# pending_count HOME
pending_count() {
  local home="$1"
  local dir="$home/.skill-fog/pending"
  if [ ! -d "$dir" ]; then
    echo 0
    return
  fi
  find "$dir" -maxdepth 1 -name '*.json' | wc -l | tr -d ' '
}

# run_hook HOME SOURCE -> sets RUN_STDOUT and RUN_EXIT
run_hook() {
  local home="$1" source="$2"
  set +e
  RUN_STDOUT=$(printf '{"source":"%s"}' "$source" | HOME="$home" bash "$hook" 2>"$tmp_root/stderr.log")
  RUN_EXIT=$?
  set -e
}

# ── Scenario 1-3: startup with two pending patterns ─────────────────────────
# 1) both patterns appear in stdout, higher count first
# 2) pending dir is emptied afterward
# 3) patterns.json status flips to snoozed for both
scenario_123() {
  local scenario="scenario 1-3 (startup, ordering + cleanup + snooze)"
  local home
  home="$(mktemp -d "$tmp_root/home-123.XXXXXX")"

  create_pending "$home" "patt-high" "add pagination to the API list endpoint" 5 2
  create_pending "$home" "patt-low" "fix flaky login test" 3 2
  init_patterns_file "$home" "patt-high" "patt-low"

  run_hook "$home" "startup"

  if [ "$RUN_EXIT" -ne 0 ]; then
    fail "$scenario" "hook exited with code $RUN_EXIT (stderr: $(cat "$tmp_root/stderr.log"))"
    return
  fi

  if ! printf '%s' "$RUN_STDOUT" | grep -qF "add pagination to the API list endpoint"; then
    fail "$scenario" "stdout missing high-count pattern canonical text"
    return
  fi
  if ! printf '%s' "$RUN_STDOUT" | grep -qF "fix flaky login test"; then
    fail "$scenario" "stdout missing low-count pattern canonical text"
    return
  fi

  local line_high line_low
  line_high=$(printf '%s' "$RUN_STDOUT" | grep -nF "add pagination to the API list endpoint" | head -1 | cut -d: -f1)
  line_low=$(printf '%s' "$RUN_STDOUT" | grep -nF "fix flaky login test" | head -1 | cut -d: -f1)
  if [ -z "$line_high" ] || [ -z "$line_low" ] || [ "$line_high" -ge "$line_low" ]; then
    fail "$scenario" "expected higher-count pattern (count=5) before lower-count pattern (count=3) in stdout, got line_high=$line_high line_low=$line_low"
    return
  fi

  # scenario 2: pending dir emptied
  local remaining
  remaining=$(pending_count "$home")
  if [ "$remaining" -ne 0 ]; then
    fail "$scenario" "expected 0 pending files after run, found $remaining"
    return
  fi

  # scenario 3: patterns.json status -> snoozed
  local status_high status_low
  status_high=$(pattern_status "$home" "patt-high")
  status_low=$(pattern_status "$home" "patt-low")
  if [ "$status_high" != "snoozed" ]; then
    fail "$scenario" "expected patt-high status=snoozed, got '$status_high'"
    return
  fi
  if [ "$status_low" != "snoozed" ]; then
    fail "$scenario" "expected patt-low status=snoozed, got '$status_low'"
    return
  fi

  pass "$scenario"
}

# ── Scenario 4: source=compact -> no output, pending preserved ──────────────
scenario_4() {
  local scenario="scenario 4 (source=compact, no injection, pending preserved)"
  local home
  home="$(mktemp -d "$tmp_root/home-4.XXXXXX")"

  create_pending "$home" "patt-a" "summarize weekly report" 4 2
  create_pending "$home" "patt-b" "generate invoice pdf" 3 2
  init_patterns_file "$home" "patt-a" "patt-b"

  run_hook "$home" "compact"

  if [ "$RUN_EXIT" -ne 0 ]; then
    fail "$scenario" "hook exited with code $RUN_EXIT (stderr: $(cat "$tmp_root/stderr.log"))"
    return
  fi

  if [ -n "$RUN_STDOUT" ]; then
    fail "$scenario" "expected empty stdout for source=compact, got: $RUN_STDOUT"
    return
  fi

  local remaining
  remaining=$(pending_count "$home")
  if [ "$remaining" -ne 2 ]; then
    fail "$scenario" "expected 2 pending files preserved, found $remaining"
    return
  fi

  local status_a status_b
  status_a=$(pattern_status "$home" "patt-a")
  status_b=$(pattern_status "$home" "patt-b")
  if [ "$status_a" != "active" ] || [ "$status_b" != "active" ]; then
    fail "$scenario" "expected statuses to remain active, got patt-a='$status_a' patt-b='$status_b'"
    return
  fi

  pass "$scenario"
}

# ── Scenario 5: 6+ pending patterns -> only top 5 by count are shown/consumed
scenario_5() {
  local scenario="scenario 5 (6 pending patterns, only top 5 shown and consumed)"
  local home
  home="$(mktemp -d "$tmp_root/home-5.XXXXXX")"

  create_pending "$home" "patt-rank-1" "canonical-rank-1" 60 2
  create_pending "$home" "patt-rank-2" "canonical-rank-2" 50 2
  create_pending "$home" "patt-rank-3" "canonical-rank-3" 40 2
  create_pending "$home" "patt-rank-4" "canonical-rank-4" 30 2
  create_pending "$home" "patt-rank-5" "canonical-rank-5" 20 2
  create_pending "$home" "patt-rank-6" "canonical-rank-6" 10 2
  init_patterns_file "$home" \
    "patt-rank-1" "patt-rank-2" "patt-rank-3" \
    "patt-rank-4" "patt-rank-5" "patt-rank-6"

  run_hook "$home" "startup"

  if [ "$RUN_EXIT" -ne 0 ]; then
    fail "$scenario" "hook exited with code $RUN_EXIT (stderr: $(cat "$tmp_root/stderr.log"))"
    return
  fi

  if ! printf '%s' "$RUN_STDOUT" | grep -qF "You have 6 repeated pattern(s) pending review."; then
    fail "$scenario" "expected total count of 6 in header, got: $(printf '%s' "$RUN_STDOUT" | head -1)"
    return
  fi

  local shown_count
  shown_count=$(printf '%s' "$RUN_STDOUT" | grep -cE '^[0-9]+\. "')
  if [ "$shown_count" -ne 5 ]; then
    fail "$scenario" "expected exactly 5 numbered items in stdout, found $shown_count"
    return
  fi

  if printf '%s' "$RUN_STDOUT" | grep -qF "canonical-rank-6"; then
    fail "$scenario" "lowest-count pattern (rank-6) should not appear in stdout"
    return
  fi

  for i in 1 2 3 4 5; do
    if ! printf '%s' "$RUN_STDOUT" | grep -qF "canonical-rank-$i"; then
      fail "$scenario" "expected canonical-rank-$i in stdout"
      return
    fi
  done

  local remaining
  remaining=$(pending_count "$home")
  if [ "$remaining" -ne 1 ]; then
    fail "$scenario" "expected exactly 1 pending file left over (rank-6), found $remaining"
    return
  fi

  if [ ! -f "$home/.skill-fog/pending/patt-rank-6.json" ]; then
    fail "$scenario" "expected patt-rank-6.json to remain in pending/"
    return
  fi

  local status_rank1 status_rank6
  status_rank1=$(pattern_status "$home" "patt-rank-1")
  status_rank6=$(pattern_status "$home" "patt-rank-6")
  if [ "$status_rank1" != "snoozed" ]; then
    fail "$scenario" "expected patt-rank-1 status=snoozed, got '$status_rank1'"
    return
  fi
  if [ "$status_rank6" != "active" ]; then
    fail "$scenario" "expected patt-rank-6 status to remain active, got '$status_rank6'"
    return
  fi

  pass "$scenario"
}

scenario_123
scenario_4
scenario_5

if [ "$failures" -ne 0 ]; then
  printf '\ntest-session-start: %d assertion(s) failed\n' "$failures" >&2
  exit 1
fi

printf '\ntest-session-start: all scenarios passed\n'
exit 0
