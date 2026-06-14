#!/usr/bin/env python3
"""Deterministic offline evaluator for generated skill-fog artifacts."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PASS_THRESHOLD = 80
VALID_RESULTS = {"pass", "fail", "review_required"}
VALID_ARTIFACT_TYPES = {"skill", "command", "agent"}
CRITICAL_FAILURE_ORDER = [
    "fixture_schema_error",
    "overbroad_trigger",
    "privacy_leak",
    "wrong_artifact_type",
    "missing_required_section",
    "missing_completion_evidence",
    "production_destructive_action",
]

SECRET_PATTERNS = [
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\b(?:postgres(?:ql)?|mysql|mongodb)://[^\s'\"<>]+", re.IGNORECASE),
    re.compile(r"\b(?:api[_-]?key|token|secret|password|passwd|pwd)\s*[:=]\s*[^\s'\"<>]+", re.IGNORECASE),
    re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{16,}", re.IGNORECASE),
    re.compile(r"\b[A-Za-z0-9_-]{32,}\b"),
    re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
]

OVERBROAD_TRIGGERS = {
    "always",
    "all requests",
    "any request",
    "all tasks",
    "any task",
    "every request",
    "everything",
    "anything",
    "general coding",
    "all coding",
    "when coding",
    "use always",
    "always use",
}

PROTECTED_HOME_ROOT_PATTERN = (
    r"(?:~|\$HOME|\$\{HOME\}|/home/[^/\s'\"`<>)\]}]+)"
    r"/(?:\.claude|\.codex|\.skill-fog)(?:/|\b)"
)

DESTRUCTIVE_PATTERNS = [
    re.compile(
        r"\brm\s+-(?=[A-Za-z]*r)(?=[A-Za-z]*f)[A-Za-z]+\s+"
        + PROTECTED_HOME_ROOT_PATTERN,
        re.IGNORECASE,
    ),
    re.compile(r"\brm\s+-(?=[A-Za-z]*r)(?=[A-Za-z]*f)[A-Za-z]+\s+/(?:\s|$)"),
    re.compile(r"\bgit\s+reset\s+--hard\b"),
    re.compile(r"\bgit\s+clean\s+-fdx\b"),
    re.compile(r"\bsudo\s+(?:rm|shutdown|reboot)\b"),
    re.compile(
        r"\b(?:delete|remove|clear|wipe)\b.{0,160}" + PROTECTED_HOME_ROOT_PATTERN,
        re.IGNORECASE | re.DOTALL,
    ),
    re.compile(r"\b(?:write|install|copy|move).*(?:~/.claude|/home/[^/\s]+/.claude)\b", re.IGNORECASE),
]


@dataclass
class FixtureSchemaError(Exception):
    message: str


def resolved_path(path: Path) -> Path:
    return path.expanduser().resolve(strict=False)


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def real_home_paths() -> list[Path]:
    homes: list[Path] = []
    for raw in (os.environ.get("HOME"),):
        if raw:
            homes.append(resolved_path(Path(raw)))
    try:
        import pwd

        homes.append(resolved_path(Path(pwd.getpwuid(os.getuid()).pw_dir)))
    except (ImportError, KeyError, OSError):
        pass
    unique: list[Path] = []
    for home in homes:
        if home not in unique:
            unique.append(home)
    return unique


def unsafe_install_roots() -> list[Path]:
    roots: list[Path] = []
    for home in real_home_paths():
        roots.extend(
            [
                home / ".claude",
                home / ".codex" / "skills",
                home / ".codex" / "agents",
            ]
        )
    return [resolved_path(root) for root in roots]


def validate_draft_root(draft_root: Path) -> Path:
    resolved = resolved_path(draft_root)
    for unsafe_root in unsafe_install_roots():
        if resolved == unsafe_root or is_relative_to(resolved, unsafe_root):
            raise SystemExit(f"unsafe --draft-root install path rejected: {draft_root}")

    temp_root = resolved_path(Path(tempfile.gettempdir()))
    if resolved != temp_root and not is_relative_to(resolved, temp_root):
        raise SystemExit(f"unsafe --draft-root must be under temp directory {temp_root}: {draft_root}")

    return resolved


def make_safe_draft_root() -> Path:
    return Path(tempfile.mkdtemp(prefix="skill-fog-artifact-drafts."))


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError as exc:
        raise SystemExit(f"missing fixture: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"expected JSON object in {path}")
    return data


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def text_from(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def first_string(*values: Any) -> str:
    for value in values:
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def bool_value(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "present", "complete", "completed"}
    return bool(value)


def fixture_case_id(path: Path, fixture: dict[str, Any]) -> str:
    return first_string(fixture.get("case_id"), fixture.get("id"), path.stem)


def expected_result(fixture: dict[str, Any]) -> str:
    expected = fixture.get("expected", {})
    if not isinstance(expected, dict):
        raise FixtureSchemaError("expected must be an object when present")
    result = first_string(
        fixture.get("expected_result"),
        expected.get("result"),
        expected.get("expected_result"),
    ).lower()
    if not result:
        raise FixtureSchemaError("missing expected_result, expected.result, or expected.expected_result")
    if result not in VALID_RESULTS:
        raise FixtureSchemaError(f"invalid expected_result: {result}")
    return result


def artifact_payload(fixture: dict[str, Any]) -> dict[str, Any]:
    for key in ("artifact_draft", "artifact", "draft", "input", "generated"):
        value = fixture.get(key)
        if isinstance(value, dict):
            return value
    return fixture


def artifact_type(fixture: dict[str, Any], artifact: dict[str, Any]) -> str:
    return first_string(
        artifact.get("artifact_type"),
        artifact.get("type"),
        fixture.get("artifact_type"),
        fixture.get("type"),
    ).lower()


def expected_artifact_type(fixture: dict[str, Any], artifact: dict[str, Any]) -> str:
    expected = fixture.get("expected", {})
    if not isinstance(expected, dict):
        expected = {}
    return first_string(
        fixture.get("expected_artifact_type"),
        expected.get("artifact_type"),
        artifact.get("expected_artifact_type"),
    ).lower()


def required_sections(fixture: dict[str, Any]) -> list[str]:
    declared = fixture.get("required_sections", [])
    if declared is None:
        return []
    if not isinstance(declared, list) or not all(isinstance(item, str) and item.strip() for item in declared):
        raise FixtureSchemaError("required_sections must be a list of non-empty strings")
    return [item.strip() for item in declared]


def artifact_text(fixture: dict[str, Any], artifact: dict[str, Any]) -> str:
    parts = [
        artifact.get("name"),
        artifact.get("description"),
        artifact.get("trigger"),
        artifact.get("triggers"),
        artifact.get("content"),
        artifact.get("markdown"),
        artifact.get("body"),
        artifact.get("examples"),
        fixture.get("content"),
        fixture.get("markdown"),
    ]
    return "\n".join(text_from(part) for part in parts if part is not None)


def markdown_section(text: str, section_name: str) -> str:
    heading = re.escape(section_name).replace("_", r"[_\s-]+").replace(r"\ ", r"[_\s-]+")
    pattern = re.compile(
        rf"^#+\s+{heading}\s*$"
        r"(?P<body>.*?)(?=^#+\s+\S|\Z)",
        re.IGNORECASE | re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    return match.group("body").strip() if match else ""


def markdown_section_exists(text: str, section_name: str) -> bool:
    heading = re.escape(section_name).replace("_", r"[_\s-]+").replace(r"\ ", r"[_\s-]+")
    pattern = re.compile(rf"^#+\s+{heading}\s*$", re.IGNORECASE | re.MULTILINE)
    return bool(pattern.search(text))


def trigger_text(artifact: dict[str, Any]) -> str:
    values = []
    for key in ("trigger", "triggers", "when_to_use", "activation", "description"):
        values.extend(text_from(item) for item in as_list(artifact.get(key)))
    content = text_from(artifact.get("content") or artifact.get("markdown") or artifact.get("body"))
    if content:
        values.append(markdown_section(content, "trigger"))
    return "\n".join(value for value in values if value)


def has_completion_evidence(fixture: dict[str, Any], artifact: dict[str, Any]) -> bool:
    content = text_from(artifact.get("content") or artifact.get("markdown") or artifact.get("body"))
    if markdown_section(content, "completion_evidence") or markdown_section(content, "completion evidence"):
        return True
    for source in (fixture, artifact):
        for key in ("completion_evidence", "evidence", "verification", "tested"):
            if key in source and bool_value(source.get(key)):
                return True
    return False


def confidence(fixture: dict[str, Any], artifact: dict[str, Any]) -> str:
    raw = first_string(
        artifact.get("confidence"),
        fixture.get("confidence"),
        fixture.get("expected_confidence"),
    ).lower()
    if raw in {"high", "medium", "low"}:
        return raw
    score = artifact.get("confidence_score", fixture.get("confidence_score"))
    if isinstance(score, (int, float)):
        if score < 0.5:
            return "low"
        if score < 0.75:
            return "medium"
        return "high"
    return "high"


def detect_overbroad(artifact: dict[str, Any]) -> bool:
    trigger = trigger_text(artifact).strip().lower()
    if not trigger:
        return False
    normalized = re.sub(r"\s+", " ", trigger)
    if normalized in OVERBROAD_TRIGGERS:
        return True
    if any(re.search(rf"\b{re.escape(phrase)}\b", normalized) for phrase in OVERBROAD_TRIGGERS):
        return True
    any_scope_hits = len(re.findall(r"\bany\s+(?:coding\s+)?(?:task|request|review|bug\s+fix|refactor|test\s+failure)\b", normalized))
    if any_scope_hits >= 2:
        return True
    return bool(re.search(r"\bwhenever\s+the\s+user\s+asks\b", normalized))


def detect_privacy(text: str) -> bool:
    return any(pattern.search(text) for pattern in SECRET_PATTERNS)


def detect_destructive(text: str) -> bool:
    return any(pattern.search(text) for pattern in DESTRUCTIVE_PATTERNS)


def schema_failure_result(path: Path, fixture: dict[str, Any], error: FixtureSchemaError) -> dict[str, Any]:
    return {
        "case_id": fixture_case_id(path, fixture),
        "expected_result": "fixture_schema_failure",
        "result": "fail",
        "score": 0,
        "critical_failures": ["fixture_schema_error"],
        "warnings": [error.message],
        "final_state": "fixture_schema_failed",
        "draft_path": None,
        "installed_path": None,
    }


def write_simulated_draft(draft_root: Path, case_id: str, artifact: dict[str, Any], text: str) -> str:
    safe_case_id = re.sub(r"[^a-zA-Z0-9_.-]+", "-", case_id).strip("-") or "artifact"
    artifact_kind = artifact.get("artifact_type") or artifact.get("type") or "artifact"
    safe_kind = re.sub(r"[^a-zA-Z0-9_.-]+", "-", str(artifact_kind)).strip("-") or "artifact"
    draft_root.mkdir(parents=True, exist_ok=True)
    draft_path = draft_root / f"{safe_case_id}.{safe_kind}.md"
    draft_path.write_text(text or json.dumps(artifact, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    return str(draft_path)


def evaluate(path: Path, draft_root: Path) -> dict[str, Any]:
    fixture = load_json(path)
    artifact = artifact_payload(fixture)
    case_id = fixture_case_id(path, fixture)
    try:
        expected = expected_result(fixture)
        required = required_sections(fixture)
    except FixtureSchemaError as exc:
        return schema_failure_result(path, fixture, exc)
    actual_type = artifact_type(fixture, artifact)
    required_type = expected_artifact_type(fixture, artifact)
    text = artifact_text(fixture, artifact)
    content = text_from(artifact.get("content") or artifact.get("markdown") or artifact.get("body"))

    critical_failures: list[str] = []
    warnings: list[str] = []
    score = 100

    if actual_type not in VALID_ARTIFACT_TYPES:
        warnings.append("unknown_artifact_type")
        score -= 10
    if required_type and actual_type != required_type:
        critical_failures.append("wrong_artifact_type")
    if detect_overbroad(artifact):
        critical_failures.append("overbroad_trigger")
    if detect_privacy(text):
        critical_failures.append("privacy_leak")
    missing_sections = [section for section in required if not markdown_section_exists(content, section)]
    if missing_sections:
        critical_failures.append("missing_required_section")
        warnings.extend(f"missing_required_section:{section}" for section in missing_sections)
    if not has_completion_evidence(fixture, artifact):
        critical_failures.append("missing_completion_evidence")
    if detect_destructive(text):
        critical_failures.append("production_destructive_action")

    if not first_string(artifact.get("name"), fixture.get("name")):
        warnings.append("missing_name")
        score -= 10
    if len(trigger_text(artifact).strip()) < 20:
        warnings.append("weak_trigger")
        score -= 10
    if len(text.strip()) < 120:
        warnings.append("thin_artifact_content")
        score -= 10

    actual_confidence = confidence(fixture, artifact)
    if actual_confidence == "low":
        warnings.append("low_confidence")
    elif actual_confidence == "medium":
        score -= 5

    score = max(0, min(100, score))
    critical_failures = sorted(set(critical_failures), key=CRITICAL_FAILURE_ORDER.index)
    warnings = sorted(set(warnings))

    draft_path: str | None = None
    if not critical_failures:
        draft_path = write_simulated_draft(draft_root, case_id, artifact, text)

    if critical_failures:
        result = "fail"
        final_state = "failed"
    elif actual_confidence == "low":
        result = "review_required"
        final_state = "draft_review_required"
    elif score >= PASS_THRESHOLD:
        result = "pass"
        final_state = "draft_validated"
    else:
        result = "fail"
        final_state = "failed_threshold"

    if result != expected:
        warnings.append(f"expected_result_mismatch:{expected}")

    return {
        "case_id": case_id,
        "expected_result": expected,
        "result": result,
        "score": score,
        "critical_failures": critical_failures,
        "warnings": warnings,
        "final_state": final_state,
        "draft_path": draft_path,
        "installed_path": None,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate one generated artifact fixture offline.")
    parser.add_argument("--fixture", required=True, help="artifact fixture JSON path")
    parser.add_argument("--draft-root", help="temp directory for simulated drafts; created safely when omitted")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    draft_root = validate_draft_root(Path(args.draft_root)) if args.draft_root else make_safe_draft_root()
    result = evaluate(Path(args.fixture), draft_root)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result["result"] == result["expected_result"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
