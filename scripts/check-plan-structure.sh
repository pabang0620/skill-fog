#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plan_path="${1:-"$script_dir/../docs/plans/skill-fog-benchmark-improvement-plan.md"}"

python3 - "$plan_path" <<'PY'
import re
import sys
from pathlib import Path


PLAN_PATH = Path(sys.argv[1])
CHECKBOX_RE = re.compile(r"^(\s*)- \[[ xX]\]\s*(.*)$")
FIELD_RE = re.compile(r"^\s{2,}(Reason|Solution path|Evidence):\s*(.+?)\s*$")
LABEL_RE = re.compile(r"^[A-Za-z][A-Za-z0-9 /-]*:\s*$")
REQUIRED_FIELDS = ("Reason", "Solution path", "Evidence")


def fail(message):
    print(f"check-plan-structure: {message}", file=sys.stderr)
    sys.exit(1)


if not PLAN_PATH.is_file():
    fail(f"plan file not found: {PLAN_PATH}")

lines = PLAN_PATH.read_text(encoding="utf-8").splitlines()
items = []
in_fence = False
in_checklist = False
current = None

for line_number, line in enumerate(lines, start=1):
    if line.startswith("```"):
        in_fence = not in_fence
        continue
    if in_fence:
        continue

    stripped = line.strip()
    if stripped == "Checklist:":
        in_checklist = True
        current = None
        continue
    if in_checklist and (
        stripped.startswith("## ")
        or (LABEL_RE.match(stripped) and stripped != "Checklist:")
    ):
        in_checklist = False
        current = None

    checkbox_match = CHECKBOX_RE.match(line)
    if checkbox_match:
        text = checkbox_match.group(2).strip()
        current = {
            "line": line_number,
            "text": text,
            "fields": {},
        }
        items.append(current)
        continue

    if current is None:
        continue

    field_match = FIELD_RE.match(line)
    if field_match:
        field_name, field_value = field_match.groups()
        current["fields"].setdefault(field_name, []).append((line_number, field_value))
        continue

    if stripped and not line.startswith((" ", "\t")):
        current = None

errors = []
if not items:
    errors.append("no implementation checklist items found")

for item in items:
    line_number = item["line"]
    text = item["text"]

    if not text.startswith("Task:"):
        errors.append(f"line {line_number}: checklist item must start with 'Task:'")
        continue

    task_value = text[len("Task:"):].strip()
    if not task_value:
        errors.append(f"line {line_number}: Task field must not be empty")

    for field_name in REQUIRED_FIELDS:
        values = item["fields"].get(field_name, [])
        if not values:
            errors.append(f"line {line_number}: missing '{field_name}:' field")
        elif len(values) > 1:
            first_duplicate = values[1][0]
            errors.append(
                f"line {first_duplicate}: duplicate '{field_name}:' field for item on line {line_number}"
            )
        elif not values[0][1].strip():
            errors.append(f"line {values[0][0]}: '{field_name}:' field must not be empty")

if errors:
    print(f"Plan structure check failed for {PLAN_PATH}:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(f"Plan structure check passed: {len(items)} implementation checklist items validated.")
PY
