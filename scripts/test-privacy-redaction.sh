#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# skill-fog: runtime privacy redaction regression test
# Exercises hooks/stop.sh (local path masking, no-content debug logging) and
# hooks/session-start.sh (missing-python3 guard) against isolated temporary
# HOME/PATH environments. Never touches the real ~/.skill-fog or ~/.claude.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
stop_hook="$repo_dir/hooks/stop.sh"
session_start_hook="$repo_dir/hooks/session-start.sh"

if ! command -v python3 &>/dev/null; then
  printf 'test-privacy-redaction: python3 is required but was not found\n' >&2
  exit 1
fi

if [ ! -f "$stop_hook" ]; then
  printf 'test-privacy-redaction: hook not found at %s\n' "$stop_hook" >&2
  exit 1
fi

if [ ! -f "$session_start_hook" ]; then
  printf 'test-privacy-redaction: hook not found at %s\n' "$session_start_hook" >&2
  exit 1
fi

failures=0
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-fog-privacy-redaction-test.XXXXXX")"

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

# ── shared fixture: a transcript with a local-path message and a noise-prefixed
#    message, both carrying a distinct secret marker that must never survive
#    into patterns.json examples or into the log files. ──────────────────────
SECRET_HOME_MARKER="secret-app"
SECRET_USERS_MARKER="x-confidential"
SECRET_LOG_MARKER="SECRETMARKERXYZ123"

build_transcript() {
  local path="$1"
  cat > "$path" <<EOF
{"role":"user","content":"/home/alice/project/${SECRET_HOME_MARKER} 배포해줘 알아서 진행해줘"}
{"role":"user","content":"check /Users/bob/work/${SECRET_USERS_MARKER}.md please and report back"}
{"role":"user","content":"[skill-fog] ${SECRET_LOG_MARKER} should never leak into any log file after this fix"}
EOF
}

run_stop_hook() {
  local home="$1"
  local session_id="$2"
  local transcript_path="$3"

  python3 - "$session_id" "$transcript_path" <<'PY' | HOME="$home" "$stop_hook"
import json
import sys

print(json.dumps({
    "session_id": sys.argv[1],
    "transcript_path": sys.argv[2],
}))
PY
}

# ── Scenario 1 + 2: mask_secrets local-path redaction + content-free logging ─
scenario_home="$tmp_root/home-stop"
mkdir -p "$scenario_home"
transcript="$tmp_root/transcript.jsonl"
build_transcript "$transcript"

run_stop_hook "$scenario_home" "privacy-test-session" "$transcript" >/dev/null 2>&1 || true

patterns_file="$scenario_home/.skill-fog/patterns.json"
logs_dir="$scenario_home/.skill-fog/logs"

if [ ! -f "$patterns_file" ]; then
  fail "mask_secrets local path redaction" "patterns.json was not created at $patterns_file"
else
  patterns_json="$(cat "$patterns_file")"
  if printf '%s' "$patterns_json" | grep -qF "/home/alice"; then
    fail "mask_secrets local path redaction" "raw /home/alice path leaked into patterns.json examples"
  elif printf '%s' "$patterns_json" | grep -qF "$SECRET_HOME_MARKER"; then
    fail "mask_secrets local path redaction" "raw marker '$SECRET_HOME_MARKER' leaked into patterns.json examples"
  elif printf '%s' "$patterns_json" | grep -qF "/Users/bob"; then
    fail "mask_secrets local path redaction" "raw /Users/bob path leaked into patterns.json examples"
  elif printf '%s' "$patterns_json" | grep -qF "$SECRET_USERS_MARKER"; then
    fail "mask_secrets local path redaction" "raw marker '$SECRET_USERS_MARKER' leaked into patterns.json examples"
  else
    pass "mask_secrets local path redaction"
  fi
fi

if [ ! -d "$logs_dir" ]; then
  fail "log content redaction" "logs directory was not created at $logs_dir"
else
  if grep -rqF "$SECRET_LOG_MARKER" "$logs_dir" 2>/dev/null; then
    fail "log content redaction" "raw message content ('$SECRET_LOG_MARKER') leaked into ~/.skill-fog/logs/*.log"
  else
    pass "log content redaction"
  fi
fi

# ── Scenario 3: session-start.sh with python3 absent from PATH ──────────────
scenario_home2="$tmp_root/home-session-start"
mkdir -p "$scenario_home2"

restricted_bin="$tmp_root/restricted-bin"
mkdir -p "$restricted_bin"
real_cat="$(command -v cat)"
real_bash="$(command -v bash)"
ln -s "$real_cat" "$restricted_bin/cat"
ln -s "$real_bash" "$restricted_bin/bash"

stdout_file="$tmp_root/session-start.stdout"
stderr_file="$tmp_root/session-start.stderr"
set +e
printf '%s' '{"source":"startup"}' \
  | HOME="$scenario_home2" PATH="$restricted_bin" bash "$session_start_hook" \
  >"$stdout_file" 2>"$stderr_file"
exit_code=$?
set -e

if [ "$exit_code" -ne 0 ]; then
  fail "session-start.sh missing python3" "expected exit code 0, got $exit_code"
elif [ -s "$stdout_file" ]; then
  fail "session-start.sh missing python3" "expected empty stdout, got: $(cat "$stdout_file")"
elif [ ! -s "$stderr_file" ]; then
  fail "session-start.sh missing python3" "expected a warning on stderr, got nothing"
else
  pass "session-start.sh missing python3"
fi

echo ""
if [ "$failures" -eq 0 ]; then
  echo "All privacy redaction scenarios passed."
  exit 0
else
  echo "$failures scenario(s) failed."
  exit 1
fi
