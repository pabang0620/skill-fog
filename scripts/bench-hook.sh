#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
hook_path="$repo_dir/hooks/stop.sh"
fixtures_dir="$repo_dir/fixtures/transcripts"

assert_only=0
benchmark_only=0
json_output=0
debug=0
runs=30
warmups=3
baseline_path="$repo_dir/docs/benchmarks/hook-baseline.md"
warn_p95_ms=""
fail_p95_ms=""

usage() {
  cat <<'EOF'
Usage: scripts/bench-hook.sh [--assert-only|--benchmark-only] [--runs N] [--warmups N] [--json] [--warn-p95-ms N] [--fail-p95-ms N] [--debug]

Runs the Phase 1B hook fixture assertions and benchmark harness.
All hook executions use a mktemp HOME and never write to the real HOME.
Markdown benchmark table output is the default. Use --json for machine-readable output.
EOF
}

fail() {
  printf 'bench-hook: %s\n' "$*" >&2
  exit 1
}

debug_log() {
  if [ "$debug" -eq 1 ]; then
    printf 'bench-hook debug: %s\n' "$*" >&2
  fi
}

default_threshold_from_baseline() {
  local label="$1"
  local fallback="$2"
  local value=""
  if [ -f "$baseline_path" ]; then
    value="$(
      python3 - "$baseline_path" "$label" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
label = sys.argv[2]
text = path.read_text(encoding="utf-8")
pattern = rf"{re.escape(label)} if p95 exceeds `?([0-9]+(?:\.[0-9]+)?)\s*ms`?"
match = re.search(pattern, text, flags=re.IGNORECASE)
print(match.group(1) if match else "")
PY
    )"
  fi
  printf '%s\n' "${value:-$fallback}"
}

validate_non_negative_number() {
  local label="$1"
  local value="$2"
  python3 - "$label" "$value" <<'PY'
import math
import sys

label = sys.argv[1]
value = sys.argv[2]
try:
    parsed = float(value)
except ValueError:
    raise SystemExit(f"{label} must be a non-negative number")
if not math.isfinite(parsed) or parsed < 0:
    raise SystemExit(f"{label} must be a non-negative number")
PY
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --assert-only)
      assert_only=1
      ;;
    --benchmark-only)
      benchmark_only=1
      ;;
    --json)
      json_output=1
      ;;
    --debug)
      debug=1
      ;;
    --runs)
      shift
      [ "${1:-}" ] || fail "--runs requires a value"
      runs="$1"
      ;;
    --warmups)
      shift
      [ "${1:-}" ] || fail "--warmups requires a value"
      warmups="$1"
      ;;
    --warn-p95-ms)
      shift
      [ "${1:-}" ] || fail "--warn-p95-ms requires a value"
      warn_p95_ms="$1"
      ;;
    --fail-p95-ms)
      shift
      [ "${1:-}" ] || fail "--fail-p95-ms requires a value"
      fail_p95_ms="$1"
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

[ "$assert_only" -eq 1 ] && [ "$benchmark_only" -eq 1 ] && \
  fail "--assert-only and --benchmark-only cannot be used together"

case "$runs" in
  ''|*[!0-9]*) fail "--runs must be a non-negative integer" ;;
esac
case "$warmups" in
  ''|*[!0-9]*) fail "--warmups must be a non-negative integer" ;;
esac
[ "$runs" -gt 0 ] || fail "--runs must be greater than 0"

warn_p95_ms="${warn_p95_ms:-$(default_threshold_from_baseline "Warn" "7000")}"
fail_p95_ms="${fail_p95_ms:-$(default_threshold_from_baseline "Fail" "10000")}"
case "$warn_p95_ms" in
  ''|*[!0-9.]*|*.*.*) fail "--warn-p95-ms must be a non-negative number" ;;
esac
case "$fail_p95_ms" in
  ''|*[!0-9.]*|*.*.*) fail "--fail-p95-ms must be a non-negative number" ;;
esac
validate_non_negative_number "--warn-p95-ms" "$warn_p95_ms" || fail "--warn-p95-ms must be a non-negative number"
validate_non_negative_number "--fail-p95-ms" "$fail_p95_ms" || fail "--fail-p95-ms must be a non-negative number"

[ -x "$hook_path" ] || fail "hook is not executable: $hook_path"
[ -d "$fixtures_dir" ] || fail "fixtures directory missing: $fixtures_dir"

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/skill-fog-bench-hook.XXXXXX")"
cleanup() {
  rm -rf "$temp_root"
}
trap cleanup EXIT

missing=()
require_fixture() {
  local path="$1"
  if [ ! -f "$path" ]; then
    missing+=("$path")
  fi
}

run_hook() {
  local temp_home="$1"
  local session_id="$2"
  local transcript_path="$3"

  python3 - "$session_id" "$transcript_path" <<'PY' | HOME="$temp_home" "$hook_path"
import json
import sys

print(json.dumps({
    "session_id": sys.argv[1],
    "transcript_path": sys.argv[2],
}))
PY
}

with_temp_home() {
  mktemp -d "$temp_root/home.XXXXXX"
}

assert_pending_for_fixture() {
  local fixture="$1"
  local label="$2"
  local temp_home
  temp_home="$(with_temp_home)"

  local split_a="$temp_home/${label}-session-a.jsonl"
  local split_b="$temp_home/${label}-session-b.jsonl"

  python3 - "$fixture" "$split_a" "$split_b" <<'PY'
import json
import re
import sys
from pathlib import Path

fixture = Path(sys.argv[1])
split_a = Path(sys.argv[2])
split_b = Path(sys.argv[3])
groups = {}

def text_parts(content):
    if isinstance(content, str):
        if content:
            yield content
    elif isinstance(content, list):
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") != "text":
                continue
            text = item.get("text", "")
            if isinstance(text, str) and text:
                yield text

def normalize_message(text):
    text = text.lower()
    text = re.sub(r"[a-zA-Z0-9_/-]+\.(tsx|ts|jsx|js|py|md|json|sh|yaml|yml|env|toml)", "FILE", text)
    text = re.sub(r"[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}", "UUID", text)
    text = re.sub(r"https?://[^ ]+", "URL", text)
    text = re.sub(r"[0-9]+", "NUM", text)
    text = re.sub(r"[ \t\n]+", " ", text)
    return text.strip()[:120]

for line_number, raw in enumerate(fixture.read_text(encoding="utf-8").splitlines(), start=1):
    if not raw.strip():
        continue
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{fixture}: invalid JSONL on line {line_number}: {exc}") from exc

    is_user = obj.get("role") == "user"
    message = obj.get("message")
    if (
        not is_user
        and obj.get("type") == "user"
        and isinstance(message, dict)
        and message.get("role") == "user"
    ):
        is_user = True

    if not is_user:
        continue

    content = message.get("content") if isinstance(message, dict) else obj.get("content")
    for text in text_parts(content):
        if len(text) < 10:
            continue
        canonical = normalize_message(text)
        if canonical:
            groups.setdefault(canonical, []).append(raw)

matching = next((records for records in groups.values() if len(records) >= 2), None)
if matching is None:
    raise SystemExit(f"{fixture}: expected at least 2 user records with the same canonical pattern")

split_a.write_text("\n".join(matching[:2]) + "\n", encoding="utf-8")
split_b.write_text(matching[0] + "\n", encoding="utf-8")
PY

  run_hook "$temp_home" "bench-${label}-a" "$split_a"
  run_hook "$temp_home" "bench-${label}-b" "$split_b"

  python3 - "$temp_home" "$fixture" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
fixture = Path(sys.argv[2])
pending_dir = home / ".skill-fog" / "pending"
pending_files = sorted(pending_dir.glob("*.json")) if pending_dir.is_dir() else []

if len(pending_files) != 1:
    raise SystemExit(
        f"{fixture}: expected exactly one pending file, found {len(pending_files)}"
    )

pending = json.loads(pending_files[0].read_text(encoding="utf-8"))
if pending.get("count") != 3:
    raise SystemExit(f"{fixture}: expected pending count 3, found {pending.get('count')!r}")
if len(pending.get("sessions", [])) != 2:
    raise SystemExit(
        f"{fixture}: expected 2 sessions, found {len(pending.get('sessions', []))}"
    )
PY

  rm -rf "$temp_home"
}

assert_cursor_regression() {
  local fixture="$1"
  local temp_home
  temp_home="$(with_temp_home)"

  run_hook "$temp_home" "bench-cursor-regression" "$fixture"

  local before after
  before="$(python3 - "$temp_home" "$fixture" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
fixture = Path(sys.argv[2])
patterns_path = home / ".skill-fog" / "patterns.json"
if not patterns_path.is_file():
    raise SystemExit(f"{fixture}: patterns.json was not created")
data = json.loads(patterns_path.read_text(encoding="utf-8"))
patterns = data.get("patterns", {})
if not patterns:
    raise SystemExit(f"{fixture}: first run created no patterns")
print(json.dumps({k: v.get("count", 0) for k, v in sorted(patterns.items())}, sort_keys=True))
PY
)"

  run_hook "$temp_home" "bench-cursor-regression" "$fixture"

  after="$(python3 - "$temp_home" "$fixture" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
fixture = Path(sys.argv[2])
patterns_path = home / ".skill-fog" / "patterns.json"
data = json.loads(patterns_path.read_text(encoding="utf-8"))
print(json.dumps({k: v.get("count", 0) for k, v in sorted(data.get("patterns", {}).items())}, sort_keys=True))
PY
)"

  if [ "$before" != "$after" ]; then
    fail "$fixture: cursor regression failed; counts changed on second run: before=$before after=$after"
  fi

  rm -rf "$temp_home"
}

run_assertions() {
  local v1="$fixtures_dir/claude-jsonl-v1.jsonl"
  local v2="$fixtures_dir/claude-jsonl-v2.jsonl"
  local cursor="$fixtures_dir/cursor-regression.jsonl"

  require_fixture "$v1"
  require_fixture "$v2"
  require_fixture "$cursor"
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'bench-hook: missing assertion fixture(s):\n' >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
  fi

  assert_pending_for_fixture "$v1" "claude-jsonl-v1"
  assert_pending_for_fixture "$v2" "claude-jsonl-v2"
  assert_cursor_regression "$cursor"
}

machine_info() {
  local uname_text
  uname_text="$(uname -srm 2>/dev/null || uname -a 2>/dev/null || printf 'unknown')"
  local cpu_text="unknown"
  if command -v nproc >/dev/null 2>&1; then
    cpu_text="$(nproc) cores"
  elif command -v sysctl >/dev/null 2>&1; then
    cpu_text="$(sysctl -n hw.ncpu 2>/dev/null || printf 'unknown') cores"
  fi
  printf '%s; %s' "$uname_text" "$cpu_text"
}

git_sha() {
  git -C "$repo_dir" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown'
}

time_hook_ms() {
  local temp_home="$1"
  local session_id="$2"
  local transcript_path="$3"

  python3 - "$hook_path" "$temp_home" "$session_id" "$transcript_path" <<'PY'
import json
import os
import subprocess
import sys
import time

hook_path, temp_home, session_id, transcript_path = sys.argv[1:5]
payload = json.dumps({
    "session_id": session_id,
    "transcript_path": transcript_path,
}).encode("utf-8")
env = os.environ.copy()
env["HOME"] = temp_home

start = time.perf_counter()
subprocess.run([hook_path], input=payload, env=env, check=True, stdout=subprocess.DEVNULL)
elapsed_ms = (time.perf_counter() - start) * 1000
print(f"{elapsed_ms:.3f}")
PY
}

cursor_key() {
  local session_id="$1"
  local transcript_path="$2"

  python3 - "$session_id" "$transcript_path" <<'PY'
import hashlib
import sys

session_id, transcript_path = sys.argv[1:3]
print(hashlib.sha256(f"{session_id}\0{transcript_path}".encode("utf-8", errors="replace")).hexdigest()[:32])
PY
}

incremental_start_offset() {
  local transcript_path="$1"

  python3 - "$transcript_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_bytes().splitlines(keepends=True)
tail_line_count = min(100, len(lines))
print(sum(len(line) for line in lines[:-tail_line_count]))
PY
}

prepare_incremental_home_template() {
  local template_home="$1"
  local session_id="$2"
  local transcript_path="$3"
  local start_offset="$4"
  local key="$5"
  local cursor_dir="$template_home/.skill-fog/transcript-cursors"

  mkdir -p "$cursor_dir"
  python3 - "$cursor_dir/${key}.json" "$session_id" "$transcript_path" "$start_offset" <<'PY'
import datetime as dt
import json
import sys
from pathlib import Path

cursor_path = Path(sys.argv[1])
session_id = sys.argv[2]
transcript_path = sys.argv[3]
start_offset = int(sys.argv[4])

cursor_path.write_text(json.dumps({
    "session_id": session_id,
    "transcript_path": transcript_path,
    "byte_offset": start_offset,
    "updated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}, indent=2) + "\n", encoding="utf-8")
PY
}

verify_incremental_run_advanced() {
  local temp_home="$1"
  local fixture="$2"
  local cursor_key_value="$3"
  local start_offset="$4"
  local cursor_file="$temp_home/.skill-fog/transcript-cursors/${cursor_key_value}.json"

  python3 - "$cursor_file" "$fixture" "$start_offset" <<'PY'
import json
import sys
from pathlib import Path

cursor_file = Path(sys.argv[1])
fixture = Path(sys.argv[2])
start_offset = int(sys.argv[3])
file_size = fixture.stat().st_size

if not cursor_file.is_file():
    raise SystemExit(f"{fixture}: incremental benchmark did not write cursor {cursor_file}")

cursor = json.loads(cursor_file.read_text(encoding="utf-8"))
after_offset = int(cursor.get("byte_offset") or 0)
if after_offset <= start_offset:
    raise SystemExit(
        f"{fixture}: incremental benchmark cursor did not advance "
        f"(start={start_offset}, after={after_offset})"
    )
if after_offset > file_size:
    raise SystemExit(
        f"{fixture}: incremental benchmark cursor exceeded file size "
        f"(after={after_offset}, size={file_size})"
    )
PY
}

bench_one() {
  local fixture="$1"
  local mode="$2"
  local times_file="$3"
  local bench_root="$4"

  : > "$times_file"

  if [ "$mode" = "incremental" ]; then
    local session_id="bench-large-incremental"
    local cursor_key_value
    cursor_key_value="$(cursor_key "$session_id" "$fixture")"
    local start_offset
    start_offset="$(incremental_start_offset "$fixture")"
    local template_home="$bench_root/template-large-incremental"
    mkdir -p "$template_home"
    prepare_incremental_home_template "$template_home" "$session_id" "$fixture" "$start_offset" "$cursor_key_value"

    for ((i = 1; i <= warmups; i++)); do
      local temp_home="$bench_root/warmup-large-incremental-${i}"
      mkdir -p "$temp_home"
      cp -a "$template_home/." "$temp_home/"
      time_hook_ms "$temp_home" "$session_id" "$fixture" >/dev/null
      verify_incremental_run_advanced "$temp_home" "$fixture" "$cursor_key_value" "$start_offset"
    done
    for ((i = 1; i <= runs; i++)); do
      local temp_home="$bench_root/run-large-incremental-${i}"
      mkdir -p "$temp_home"
      cp -a "$template_home/." "$temp_home/"
      time_hook_ms "$temp_home" "$session_id" "$fixture" >> "$times_file"
      verify_incremental_run_advanced "$temp_home" "$fixture" "$cursor_key_value" "$start_offset"
    done
  else
    for ((i = 1; i <= warmups; i++)); do
      local temp_home="$bench_root/warmup-${mode}-${i}"
      mkdir -p "$temp_home"
      time_hook_ms "$temp_home" "bench-${mode}-${i}" "$fixture" >/dev/null
    done
    for ((i = 1; i <= runs; i++)); do
      local temp_home="$bench_root/run-${mode}-${i}"
      mkdir -p "$temp_home"
      time_hook_ms "$temp_home" "bench-${mode}-${i}" "$fixture" >> "$times_file"
    done
  fi
}

run_benchmarks() {
  local small="$fixtures_dir/small.jsonl"
  local medium="$fixtures_dir/medium.jsonl"
  local large="$fixtures_dir/large-incremental.jsonl"

  require_fixture "$small"
  require_fixture "$medium"
  require_fixture "$large"
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'bench-hook: missing benchmark fixture(s):\n' >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
  fi

  local bench_root
  bench_root="$(mktemp -d "$temp_root/bench.XXXXXX")"

  local date_utc machine
  date_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  machine="$(machine_info)"

  local small_times="$bench_root/small.times"
  local medium_times="$bench_root/medium.times"
  local large_times="$bench_root/large.times"

  bench_one "$small" "small" "$small_times" "$bench_root"
  bench_one "$medium" "medium" "$medium_times" "$bench_root"
  bench_one "$large" "incremental" "$large_times" "$bench_root"

  debug_log "benchmark metadata: runs=$runs warmups=$warmups warn_p95_ms=$warn_p95_ms fail_p95_ms=$fail_p95_ms json=$json_output"

  python3 - "$date_utc" "$machine" "$(git_sha)" "$runs" "$warmups" "$warn_p95_ms" "$fail_p95_ms" "$json_output" "$repo_dir" \
    "$small" "$small_times" \
    "$medium" "$medium_times" \
    "$large" "$large_times" <<'PY'
import json
import math
import platform
import sys
from pathlib import Path

date_utc = sys.argv[1]
machine = sys.argv[2] or platform.platform()
git_sha = sys.argv[3] or "unknown"
runs = int(sys.argv[4])
warmups = int(sys.argv[5])
warn_p95_ms = float(sys.argv[6])
fail_p95_ms = float(sys.argv[7])
json_output = sys.argv[8] == "1"
repo_dir = Path(sys.argv[9])
pairs = sys.argv[10:]

def percentile(values, pct):
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * (pct / 100.0)
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return ordered[int(rank)]
    weight = rank - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight

def fixture_name(path):
    return path.stem

def display_path(path):
    try:
        return str(path.relative_to(repo_dir))
    except ValueError:
        return str(path)

def status_for(p95):
    if p95 > fail_p95_ms:
        return "performance_budget_exceeded"
    if p95 > warn_p95_ms:
        return "warn"
    return "ok"

results = []
violations = []

for fixture_arg, times_arg in zip(pairs[0::2], pairs[1::2]):
    fixture = Path(fixture_arg)
    times = [
        float(line.strip())
        for line in Path(times_arg).read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if len(times) != runs:
        raise SystemExit(f"{fixture}: expected {runs} timing rows, found {len(times)}")
    byte_size = fixture.stat().st_size
    with fixture.open("rb") as f:
        line_count = sum(1 for _ in f)
    p50 = percentile(times, 50)
    p95 = percentile(times, 95)
    max_ms = max(times)
    status = status_for(p95)
    result = {
        "name": fixture_name(fixture),
        "path": display_path(fixture),
        "bytes": byte_size,
        "lines": line_count,
        "p50_ms": round(p50, 3),
        "p95_ms": round(p95, 3),
        "max_ms": round(max_ms, 3),
        "status": status,
    }
    results.append(result)
    if status == "performance_budget_exceeded":
        violations.append({
            "reason": "performance_budget_exceeded",
            "fixture": result["name"],
            "p95_ms": result["p95_ms"],
            "threshold_ms": fail_p95_ms,
        })

if json_output:
    print(json.dumps({
        "schema_version": 1,
        "generated_at": date_utc,
        "git_sha": git_sha,
        "machine": machine,
        "runs": runs,
        "warmups": warmups,
        "thresholds": {
            "warn_p95_ms": warn_p95_ms,
            "fail_p95_ms": fail_p95_ms,
        },
        "fixtures": results,
        "violations": violations,
    }, sort_keys=True, indent=2))
else:
    print("| Fixture | Bytes | Lines | p50 ms | p95 ms | Max ms | Status | Runs | Warmups | Date | Machine |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | --- | --- |")
    for result in results:
        print(
            f"| `{result['path']}` | {result['bytes']} | {result['lines']} | "
            f"{result['p50_ms']:.3f} | {result['p95_ms']:.3f} | {result['max_ms']:.3f} | "
            f"{result['status']} | {runs} | {warmups} | {date_utc} | {machine} |"
        )
    for violation in violations:
        print(
            "performance_budget_exceeded "
            f"fixture={violation['fixture']} "
            f"p95_ms={violation['p95_ms']:.3f} "
            f"threshold_ms={violation['threshold_ms']:.3f}",
            file=sys.stderr,
        )

if violations:
    raise SystemExit(2)
PY

  rm -rf "$bench_root"
}

if [ "$benchmark_only" -eq 0 ]; then
  run_assertions
fi

if [ "$assert_only" -eq 0 ]; then
  missing=()
  run_benchmarks
fi
