#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
fixtures_dir="$repo_dir/fixtures/artifacts"
evaluator="$script_dir/eval-artifacts.py"

case_id=""
run_all=0

usage() {
  cat <<'EOF'
Usage: scripts/run-evals.sh --case CASE_ID
       scripts/run-evals.sh --all

Runs Phase 5 artifact eval fixtures offline. The runner writes simulated drafts
only under a temporary directory and never writes to ~/.claude or real HOME.
EOF
}

fail() {
  printf 'run-evals: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --case)
      shift
      [ "${1:-}" ] || fail "--case requires a value"
      case_id="$1"
      ;;
    --all)
      run_all=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

[ -n "$case_id" ] && [ "$run_all" -eq 1 ] && fail "choose either --case or --all"
[ -n "$case_id" ] || [ "$run_all" -eq 1 ] || fail "choose --case CASE_ID or --all"
[ -x "$evaluator" ] || fail "evaluator is not executable: $evaluator"
[ -d "$fixtures_dir" ] || fail "fixtures directory missing: $fixtures_dir"

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-fog-artifact-evals.XXXXXX")"
cleanup() {
  rm -rf "$temp_root"
}
trap cleanup EXIT

fixture_for_case() {
  local selected="$1"
  case "$selected" in
    ''|*[!A-Za-z0-9_.-]*)
      fail "case id must contain only letters, numbers, underscore, dot, or hyphen: $selected"
      ;;
  esac
  local path="$fixtures_dir/${selected}.json"
  if [ ! -f "$path" ]; then
    fail "missing fixture for case '$selected': $path"
  fi
  printf '%s\n' "$path"
}

run_fixture() {
  local fixture="$1"
  HOME="$temp_root/home" python3 "$evaluator" \
    --fixture "$fixture" \
    --draft-root "$temp_root/drafts"
}

if [ "$run_all" -eq 1 ]; then
  mapfile -t fixtures < <(find "$fixtures_dir" -maxdepth 1 -type f -name '*.json' | sort)
  [ "${#fixtures[@]}" -gt 0 ] || fail "no artifact fixtures found in $fixtures_dir"

  outputs=()
  status=0
  for fixture in "${fixtures[@]}"; do
    if output="$(run_fixture "$fixture")"; then
      outputs+=("$output")
    else
      status=1
      outputs+=("$output")
    fi
  done

  python3 - "${outputs[@]}" <<'PY'
import json
import sys

cases = [json.loads(item) for item in sys.argv[1:]]
ok = all(case["result"] == case["expected_result"] for case in cases)
print(json.dumps({"ok": ok, "cases": cases}, ensure_ascii=False, indent=2, sort_keys=True))
PY
  exit "$status"
fi

selected_fixture="$(fixture_for_case "$case_id")"
run_fixture "$selected_fixture"
