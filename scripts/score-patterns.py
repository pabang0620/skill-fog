#!/usr/bin/env python3
"""Deterministic offline scorer for skill-fog pattern candidates."""

from __future__ import annotations

import argparse
import copy
import json
import math
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


VALID_TYPES = {"skill", "command", "agent", "unknown"}
AUTO_DECISIONS = {"accept", "accepted", "auto", "auto_propose", "propose"}
REVIEW_DECISIONS = {"review", "review_required", "needs_review"}
SUPPRESS_DECISIONS = {"reject", "rejected", "suppress", "suppressed", "skip"}

REDACTION_RULES = [
    (
        "privacy.secret.aws_access_key",
        re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        "[REDACTED:TOKEN]",
        -20,
    ),
    (
        "privacy.secret.db_url",
        re.compile(r"\b(?:postgres(?:ql)?|mysql|mongodb)://[^\s'\"<>]+", re.IGNORECASE),
        "[REDACTED:DATABASE_URL]",
        -20,
    ),
    (
        "privacy.secret.assignment",
        re.compile(
            r"\b(?:api[_-]?key|token|secret|password|passwd|pwd)\s*[:=]\s*[^\s'\"<>]+",
            re.IGNORECASE,
        ),
        "[REDACTED:TOKEN]",
        -20,
    ),
    (
        "privacy.secret.bearer",
        re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{16,}", re.IGNORECASE),
        "[REDACTED:TOKEN]",
        -20,
    ),
    (
        "privacy.secret.long_token",
        re.compile(r"\b[A-Za-z0-9_-]{32,}\b"),
        "[REDACTED:TOKEN]",
        -20,
    ),
    (
        "privacy.email",
        re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
        "[REDACTED:EMAIL]",
        -20,
    ),
    (
        "privacy.local_path",
        re.compile(r"(?<!\w)(?:/home|/Users|/var|/tmp)/[^\s'\"<>]+"),
        "[REDACTED:PATH]",
        -10,
    ),
    (
        "privacy.private_url",
        re.compile(
            r"\bhttps?://(?:localhost|127\.0\.0\.1|10\.|192\.168\.|"
            r"172\.(?:1[6-9]|2[0-9]|3[0-1])\.)[^\s'\"<>]*",
            re.IGNORECASE,
        ),
        "[REDACTED:PRIVATE_URL]",
        -20,
    ),
]

NOISE_RULES = [
    ("noise.too_short", re.compile(r"^.{0,9}$", re.DOTALL), -30),
    (
        "noise.only_ack",
        re.compile(r"^(ok|okay|yes|no|네|응|아니|좋아|ㅇㅋ|thanks?|감사)$", re.IGNORECASE),
        -30,
    ),
    (
        "noise.polite_closure",
        re.compile(r"\b(thanks?|thank you).*\b(worked|fixed|done)\b", re.IGNORECASE),
        -30,
    ),
    (
        "noise.benign_repeat",
        re.compile(
            r"\b(please\s+)?run tests again\b|\bcontinue from (the )?previous step\b",
            re.IGNORECASE,
        ),
        -30,
    ),
    (
        "noise.stack_trace",
        re.compile(r"\b(traceback|stack trace|node_modules|at .+\(.+:\d+:\d+\))\b", re.IGNORECASE),
        -30,
    ),
    ("noise.generated_blob", re.compile(r"^[{}\[\],:0-9A-Za-z_\"'\s.-]{160,}$"), -20),
    (
        "noise.question_only",
        re.compile(r"^(what|why|how|when|where|누구|뭐|왜|어떻게)\b.*\?$", re.IGNORECASE),
        -10,
    ),
]

ACTION_VERBS = {
    "add",
    "analyze",
    "build",
    "check",
    "clean",
    "continue",
    "convert",
    "create",
    "debug",
    "document",
    "fix",
    "generate",
    "implement",
    "install",
    "investigate",
    "lint",
    "merge",
    "plan",
    "refactor",
    "remove",
    "review",
    "rotate",
    "run",
    "sanitize",
    "score",
    "summarize",
    "test",
    "turn",
    "update",
    "verify",
    "write",
}

KOREAN_ACTION_SIGNALS = ("해줘", "고쳐", "만들", "작성", "검토", "분석", "수정", "구현", "테스트", "정리")
ARTIFACT_SIGNALS = {
    "skill": ("skill", "workflow", "reference", "guide", "rubric", "checklist", "스킬"),
    "command": ("command", "cli", "script", "shell", "hook", "slash", "커맨드", "명령"),
    "agent": ("agent", "reviewer", "specialist", "engineer", "planner", "architect", "에이전트"),
}


def component(points: int, limit_name: str, limit: int, evidence: str) -> dict[str, Any]:
    return {"points": points, limit_name: limit, "evidence": evidence}


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    raw = value.strip()
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def redaction_reason(rule_id: str) -> str:
    if rule_id in {
        "privacy.secret.aws_access_key",
        "privacy.secret.assignment",
        "privacy.secret.bearer",
        "privacy.secret.long_token",
    }:
        return "token_like_secret"
    if rule_id == "privacy.email":
        return "email_address"
    if rule_id == "privacy.secret.db_url":
        return "database_url"
    if rule_id == "privacy.local_path":
        return "local_path"
    if rule_id == "privacy.private_url":
        return "private_url"
    return rule_id


def redact_pattern(pattern: dict[str, Any]) -> tuple[dict[str, Any], list[str], int, bool, list[dict[str, str]]]:
    redacted = copy.deepcopy(pattern)
    rule_ids: list[str] = []
    penalties: list[int] = []
    redactions: list[dict[str, str]] = []

    def redact_text(field: str, text: str) -> str:
        result = text
        matched: list[tuple[str, str]] = []
        for rule_id, regex, replacement, penalty in REDACTION_RULES:
            if regex.search(result):
                original = result
                result = regex.sub(replacement, result)
                if rule_id not in rule_ids:
                    rule_ids.append(rule_id)
                    penalties.append(penalty)
                matched.append((rule_id, redaction_reason(rule_id)))
                if rule_id == "privacy.secret.db_url" and re.search(
                    r"\b(?:postgres(?:ql)?|mysql|mongodb)://[^/\s'\"<>]+:[^@\s'\"<>]+@",
                    original,
                    re.IGNORECASE,
                ):
                    matched.append((rule_id, "credential_in_url"))
        for rule_id, reason in matched:
            redactions.append(
                {
                    "field": field,
                    "rule_id": rule_id,
                    "reason": reason,
                    "redacted_preview": result,
                }
            )
        return result

    redacted["canonical"] = redact_text("canonical", str(redacted.get("canonical", "")))
    redacted["examples"] = [
        redact_text(f"examples[{index}]", str(example))
        for index, example in enumerate(redacted.get("examples", []) or [])
    ]
    penalty = min(penalties) if penalties else 0
    redaction_succeeded = bool(rule_ids)
    return redacted, rule_ids, penalty, redaction_succeeded, redactions


def noise_penalty(text: str) -> tuple[int, str]:
    matches: list[tuple[str, int]] = []
    for rule_id, regex, penalty in NOISE_RULES:
        if regex.search(text.strip()):
            matches.append((rule_id, penalty))
    if not matches:
        return 0, "none"
    rule_id, penalty = min(matches, key=lambda item: item[1])
    return penalty, rule_id


def score_frequency(count: int) -> tuple[int, str]:
    if count <= 0:
        return 0, f"count={count}"
    points = min(25, 10 + max(0, count - 3) * 3)
    if count >= 8:
        points = 25
    return points, f"count={count}"


def score_session_spread(session_count: int) -> tuple[int, str]:
    if session_count <= 0:
        return 0, f"sessions={session_count}"
    points = min(20, 8 + max(0, session_count - 2) * 4)
    if session_count >= 5:
        points = 20
    return points, f"sessions={session_count}"


def score_recency(last_seen: Any, now: datetime) -> tuple[int, str]:
    parsed = parse_time(last_seen)
    if parsed is None:
        return 0, "last_seen=missing"
    age_days = max(0, math.floor((now - parsed).total_seconds() / 86400))
    if age_days <= 7:
        return 15, f"last_seen_age_days={age_days}"
    if age_days <= 30:
        return 10, f"last_seen_age_days={age_days}"
    if age_days <= 90:
        return 5, f"last_seen_age_days={age_days}"
    return 0, f"last_seen_age_days={age_days}"


def score_actionability(text: str) -> tuple[int, str]:
    lowered = text.lower()
    tokens = set(re.findall(r"[a-z][a-z0-9_-]*", lowered))
    verb_hits = sorted(tokens & ACTION_VERBS)
    object_pattern = (
        r"\b(file|doc|test|tests|api|hook|script|fixture|pattern|score|component|route|"
        r"schema|build|error|workflow|checklist|migration|deployment|email|database|url|"
        r"token|log|logs|summary|triage|cleanup)\b"
    )
    has_object = bool(re.search(object_pattern, lowered))
    korean_hits = [signal for signal in KOREAN_ACTION_SIGNALS if signal in text]

    points = 0
    evidence: list[str] = []
    if verb_hits:
        points += 10
        evidence.append("verbs=" + ",".join(verb_hits[:4]))
    if korean_hits:
        points += 10
        evidence.append("ko_actions=" + ",".join(korean_hits[:4]))
    if has_object:
        points += 7
        evidence.append("object_signal")
    if len(text.strip()) >= 25:
        points += 3
        evidence.append("specific_length")
    return min(20, points), ";".join(evidence) if evidence else "no action/object signal"


def classify_artifact(text: str, desired_type: Any = None) -> tuple[str, str, int, str]:
    lowered = text.lower()
    scores: dict[str, int] = {}
    evidence: dict[str, str] = {}
    for artifact_type, signals in ARTIFACT_SIGNALS.items():
        hits = [signal for signal in signals if signal in lowered]
        if hits:
            scores[artifact_type] = len(hits)
            evidence[artifact_type] = ",".join(hits[:4])

    if scores:
        raw_type = max(scores.items(), key=lambda item: (item[1], item[0]))[0]
        points = 20
        rule_id = f"artifact.{raw_type}:{evidence[raw_type]}"
    else:
        raw_type = "unknown"
        points = 0
        rule_id = "artifact.unknown:no explicit type signal"

    suggested_type = raw_type
    if isinstance(desired_type, str) and desired_type in VALID_TYPES and desired_type != "unknown":
        suggested_type = desired_type
        rule_id = f"{rule_id};manual.desired_type={desired_type}"
    return suggested_type, raw_type, points, rule_id


def confidence_for(raw_score: int, eligible: bool, privacy_points: int, noise_points: int) -> str:
    if not eligible or privacy_points <= -50 or noise_points <= -30:
        return "low"
    if raw_score >= 75:
        return "high"
    if raw_score >= 50:
        return "medium"
    return "low"


def base_recommendation(eligible: bool, raw_score: int, confidence: str, privacy_points: int, noise_points: int) -> str:
    if not eligible or raw_score < 40 or noise_points <= -30 or privacy_points <= -50:
        if eligible and privacy_points < 0 and privacy_points > -50:
            return "review_required"
        return "suppress"
    if eligible and raw_score >= 70 and privacy_points == 0 and confidence in {"high", "medium"}:
        return "auto_propose"
    if eligible and 40 <= raw_score < 70:
        return "review_required"
    if privacy_points < 0:
        return "review_required"
    return "suppress"


def apply_manual_override(pattern: dict[str, Any], recommendation: str, privacy_points: int) -> tuple[str, dict[str, Any], list[str]]:
    manual_decision = str(pattern.get("manual_decision", "") or "").strip().lower()
    reviewed_at = pattern.get("reviewed_at")
    desired_type = pattern.get("desired_type")
    evidence = {
        "manual_decision": manual_decision or None,
        "desired_type": desired_type if desired_type in VALID_TYPES else None,
        "reviewed_at": reviewed_at if isinstance(reviewed_at, str) and reviewed_at else None,
        "applied": False,
    }
    reasons: list[str] = []
    if not manual_decision:
        return recommendation, evidence, reasons
    if not evidence["reviewed_at"]:
        reasons.append("manual override ignored because reviewed_at is missing")
        return recommendation, evidence, reasons

    if manual_decision in AUTO_DECISIONS:
        evidence["applied"] = True
        if privacy_points < 0:
            reasons.append("manual_decision accept held for review because privacy penalty applied")
            return "review_required", evidence, reasons
        reasons.append("manual_decision promoted recommendation")
        return "auto_propose", evidence, reasons
    if manual_decision in REVIEW_DECISIONS:
        evidence["applied"] = True
        reasons.append("manual_decision requires review")
        return "review_required", evidence, reasons
    if manual_decision in SUPPRESS_DECISIONS:
        evidence["applied"] = True
        reasons.append("manual_decision suppresses recommendation")
        return "suppress", evidence, reasons

    reasons.append(f"manual override ignored because manual_decision={manual_decision!r} is unknown")
    return recommendation, evidence, reasons


def score_pattern(pid: str, pattern: dict[str, Any], now: datetime) -> dict[str, Any]:
    redacted_pattern, redaction_rule_ids, privacy_points, redaction_succeeded, redactions = redact_pattern(pattern)
    canonical = str(redacted_pattern.get("canonical", ""))
    count = int(pattern.get("count", 0) or 0)
    sessions = pattern.get("sessions", []) or []
    session_count = len(sessions) if isinstance(sessions, list) else 0
    status = str(pattern.get("status", "active") or "active")

    frequency_points, frequency_evidence = score_frequency(count)
    session_points, session_evidence = score_session_spread(session_count)
    recency_points, recency_evidence = score_recency(pattern.get("last_seen") or pattern.get("last_seen_at"), now)
    action_points, action_evidence = score_actionability(canonical)
    suggested_type, raw_suggested_type, artifact_points, artifact_evidence = classify_artifact(
        canonical,
        pattern.get("desired_type"),
    )
    noise_points, noise_rule_id = noise_penalty(canonical)

    eligibility_reasons: list[str] = []
    if count < 3:
        eligibility_reasons.append("count<3")
    if session_count < 2:
        eligibility_reasons.append("sessions<2")
    if status != "active":
        eligibility_reasons.append(f"status={status}")
    if noise_points <= -30:
        eligibility_reasons.append(f"noise={noise_rule_id}")
    if privacy_points <= -50:
        eligibility_reasons.append("privacy_penalty<=-50")
    eligible = not eligibility_reasons

    raw_score = (
        frequency_points
        + session_points
        + recency_points
        + action_points
        + artifact_points
        + noise_points
        + privacy_points
    )
    raw_score = max(0, min(100, raw_score))
    confidence = confidence_for(raw_score, eligible, privacy_points, noise_points)
    recommendation = base_recommendation(eligible, raw_score, confidence, privacy_points, noise_points)
    recommendation, manual_evidence, manual_reasons = apply_manual_override(pattern, recommendation, privacy_points)

    reasons = []
    if eligibility_reasons:
        reasons.extend(eligibility_reasons)
    if privacy_points < 0:
        reasons.append("privacy penalty applied")
    if noise_points < 0:
        reasons.append("noise penalty applied")
    reasons.extend(manual_reasons)
    if not reasons:
        reasons.append("eligible repeated pattern")

    return {
        "pid": pid,
        "canonical": canonical,
        "examples": redacted_pattern.get("examples", []) or [],
        "eligible": eligible,
        "raw_score": raw_score,
        "total_score": raw_score,
        "suggested_type": suggested_type,
        "raw_suggested_type": raw_suggested_type,
        "confidence": confidence,
        "recommendation": recommendation,
        "components": {
            "eligibility": {
                "eligible": eligible,
                "evidence": "passed" if eligible else ",".join(eligibility_reasons),
            },
            "frequency": component(frequency_points, "max", 25, frequency_evidence),
            "session_spread": component(session_points, "max", 20, session_evidence),
            "recency": component(recency_points, "max", 15, recency_evidence),
            "actionability": component(action_points, "max", 20, action_evidence),
            "artifact_fit": component(artifact_points, "max", 20, artifact_evidence),
            "noise_penalty": component(noise_points, "min", -30, noise_rule_id),
            "privacy_penalty": {
                "points": privacy_points,
                "min": -50,
                "evidence": ",".join(redaction_rule_ids) if redaction_rule_ids else "none",
                "redaction_rule_ids": redaction_rule_ids,
                "redactions": redactions,
                "redaction_succeeded": redaction_succeeded,
            },
            "manual_override": manual_evidence,
        },
        "reasons": reasons,
    }


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError as exc:
        raise SystemExit(f"missing file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"expected JSON object in {path}")
    return data


def extract_patterns(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    source = data.get("input", data)
    if isinstance(source, dict) and "patterns" in source:
        source = source["patterns"]
    if not isinstance(source, dict):
        raise SystemExit("expected a patterns object or {\"input\":{\"patterns\":...}}")
    patterns: dict[str, dict[str, Any]] = {}
    for pid, pattern in source.items():
        if isinstance(pattern, dict):
            patterns[str(pid)] = pattern
    return patterns


def score_patterns(patterns: dict[str, dict[str, Any]], now: datetime) -> list[dict[str, Any]]:
    scored = [score_pattern(pid, pattern, now) for pid, pattern in patterns.items()]
    return sorted(
        scored,
        key=lambda item: (
            {"auto_propose": 0, "review_required": 1, "suppress": 2}.get(item["recommendation"], 3),
            -int(item["total_score"]),
            item["pid"],
        ),
    )


def output_payload(scored: list[dict[str, Any]]) -> dict[str, Any]:
    return {"patterns": scored}


def as_by_pid(scored: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {item["pid"]: item for item in scored}


def is_phase3_fixture(fixture: dict[str, Any]) -> bool:
    return "phase3-scoring-fixture" in str(fixture.get("schema_version", ""))


def expected_value(expected: dict[str, Any], primary: str, alias: str) -> Any:
    if primary in expected:
        return expected[primary]
    return expected.get(alias)


def compare_recommendation_oracle(
    recommendations: Any,
    by_pid: dict[str, dict[str, Any]],
    require_full_coverage: bool,
) -> list[str]:
    failures: list[str] = []
    expected_by_pid: dict[str, Any] = {}
    seen_pids: set[str] = set()
    duplicate_pids: set[str] = set()

    if isinstance(recommendations, dict):
        expected_by_pid = dict(recommendations)
    elif isinstance(recommendations, list):
        for index, entry in enumerate(recommendations):
            if not isinstance(entry, dict):
                if require_full_coverage:
                    failures.append(f"recommendations[{index}] must be an object")
                continue
            pid = entry.get("pid")
            if not pid:
                if require_full_coverage:
                    failures.append(f"recommendations[{index}] missing pid")
                continue
            if pid in seen_pids:
                duplicate_pids.add(str(pid))
            seen_pids.add(str(pid))
            expected_by_pid[str(pid)] = entry.get("recommendation")
    elif recommendations is not None and require_full_coverage:
        failures.append("recommendations oracle must be an object or list")

    actual_pids = set(by_pid)
    if require_full_coverage:
        missing = actual_pids - set(expected_by_pid)
        extra = set(expected_by_pid) - actual_pids
        if missing:
            failures.append(f"recommendations missing scored pids: {sorted(missing)!r}")
        if extra:
            failures.append(f"recommendations include unknown pids: {sorted(extra)!r}")
        if duplicate_pids:
            failures.append(f"recommendations duplicate pids: {sorted(duplicate_pids)!r}")

    for pid, expected_label in expected_by_pid.items():
        actual = by_pid.get(pid, {}).get("recommendation")
        if actual != expected_label:
            failures.append(f"{pid} recommendation mismatch: expected {expected_label!r}, got {actual!r}")

    return failures


def compare_fixture(fixture: dict[str, Any], scored: list[dict[str, Any]]) -> list[str]:
    expected = fixture.get("expected", {})
    legacy_expected = fixture.get("expected_scoring")
    if expected is None:
        expected = {}
    if not isinstance(expected, dict):
        return ["fixture expected oracle must be an object"]
    if not expected and not legacy_expected:
        return ["fixture is missing expected oracle object"]
    failures: list[str] = []
    by_pid = as_by_pid(scored)
    phase3_fixture = is_phase3_fixture(fixture)

    if phase3_fixture:
        strict_order = expected.get("order")
        strict_recommendations = expected.get("recommendations")
        if not isinstance(strict_order, list):
            failures.append("Phase 3 fixture requires expected.order")
        elif not strict_order:
            failures.append("Phase 3 fixture requires non-empty expected.order")
        if not isinstance(strict_recommendations, (dict, list)):
            failures.append("Phase 3 fixture requires expected.recommendations")
        elif not strict_recommendations:
            failures.append("Phase 3 fixture requires non-empty expected.recommendations")

    order = expected_value(expected, "order", "expected_order")
    if order is not None:
        actual_order = [item["pid"] for item in scored]
        if list(order) != actual_order:
            failures.append(f"order mismatch: expected {list(order)!r}, got {actual_order!r}")

    recommendations = expected_value(expected, "recommendations", "recommendation_labels")
    failures.extend(compare_recommendation_oracle(recommendations, by_pid, phase3_fixture))

    redactions = expected_value(expected, "redactions", "redaction_expectations")
    if redactions is None and isinstance(legacy_expected, list):
        redactions = [
            {
                "pid": entry.get("pid"),
                "redactions": entry.get("redactions", []),
            }
            for entry in legacy_expected
            if isinstance(entry, dict) and entry.get("pid")
        ]
    if isinstance(redactions, dict):
        for pid, rule_ids in redactions.items():
            actual_rules = set(by_pid.get(pid, {}).get("components", {}).get("privacy_penalty", {}).get("redaction_rule_ids", []))
            missing = set(rule_ids) - actual_rules
            if missing:
                failures.append(f"{pid} missing redaction rule ids: {sorted(missing)!r}")
    elif isinstance(redactions, list):
        for entry in redactions:
            if not isinstance(entry, dict):
                continue
            pid = entry.get("pid")
            actual_privacy = by_pid.get(pid, {}).get("components", {}).get("privacy_penalty", {})
            actual_rules = set(actual_privacy.get("redaction_rule_ids", []))
            rule_ids = set(entry.get("rule_ids", []))
            missing = rule_ids - actual_rules
            if pid and missing:
                failures.append(f"{pid} missing redaction rule ids: {sorted(missing)!r}")
            for redaction in entry.get("redactions", []):
                if not isinstance(redaction, dict):
                    continue
                field = redaction.get("field")
                preview = redaction.get("redacted_preview")
                reason = redaction.get("reason")
                actual_redactions = actual_privacy.get("redactions", [])
                if field and preview:
                    if not any(item.get("field") == field and item.get("redacted_preview") == preview for item in actual_redactions):
                        failures.append(f"{pid} missing redacted preview for {field}: {preview!r}")
                if field and reason:
                    if not any(item.get("field") == field and item.get("reason") == reason for item in actual_redactions):
                        failures.append(f"{pid} missing redaction reason for {field}: {reason!r}")

    forbidden_values = expected.get("forbidden_output_values", [])
    if forbidden_values:
        rendered = json.dumps(output_payload(scored), ensure_ascii=False, sort_keys=True)
        for value in forbidden_values:
            if value and str(value) in rendered:
                failures.append(f"forbidden raw value appears in output: {value!r}")

    manual = expected_value(expected, "manual_overrides", "manual_override_effects")
    if manual is None and isinstance(legacy_expected, list):
        manual = []
        for entry in legacy_expected:
            if not isinstance(entry, dict):
                continue
            pid = entry.get("pid")
            input_pattern = extract_patterns(fixture).get(pid or "", {})
            if not pid or not any(key in input_pattern for key in ("manual_decision", "desired_type", "reviewed_at")):
                continue
            effect: dict[str, Any] = {
                "pid": pid,
                "raw_score_unchanged": "manual_decision" in input_pattern,
            }
            if entry.get("decision"):
                effect["recommendation"] = entry["decision"]
            if entry.get("desired_type"):
                effect["suggested_type"] = entry["desired_type"]
            manual.append(effect)
    if isinstance(manual, dict):
        manual = [{"pid": pid, **effect} for pid, effect in manual.items() if isinstance(effect, dict)]
    if isinstance(manual, list):
        for entry in manual:
            if not isinstance(entry, dict):
                continue
            pid = entry.get("pid")
            actual = by_pid.get(pid)
            if not pid or not actual:
                failures.append(f"{pid} manual override target missing")
                continue
            if "recommendation" in entry and actual.get("recommendation") != entry["recommendation"]:
                failures.append(f"{pid} manual recommendation mismatch: expected {entry['recommendation']!r}, got {actual.get('recommendation')!r}")
            if "suggested_type" in entry and actual.get("suggested_type") != entry["suggested_type"]:
                failures.append(f"{pid} manual suggested_type mismatch: expected {entry['suggested_type']!r}, got {actual.get('suggested_type')!r}")
            if entry.get("raw_score_unchanged", False):
                input_patterns = extract_patterns(fixture)
                without_override = copy.deepcopy(input_patterns[pid])
                for key in ("manual_decision", "desired_type", "reviewed_at"):
                    without_override.pop(key, None)
                rescored = score_pattern(pid, without_override, parse_now(fixture.get("now")))
                if actual.get("raw_score") != rescored.get("raw_score"):
                    failures.append(f"{pid} raw_score changed by manual override: {actual.get('raw_score')} != {rescored.get('raw_score')}")

    return failures


def parse_now(value: Any = None) -> datetime:
    parsed = parse_time(value)
    return parsed if parsed is not None else datetime.now(timezone.utc)


def run_fixture(path: Path) -> int:
    fixture = load_json(path)
    patterns = extract_patterns(fixture)
    scored = score_patterns(patterns, parse_now(fixture.get("now")))
    failures = compare_fixture(fixture, scored)
    payload = output_payload(scored)
    payload["fixture"] = str(path)
    payload["ok"] = not failures
    payload["failures"] = failures
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return 1 if failures else 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Score skill-fog patterns deterministically.")
    parser.add_argument("path", nargs="?", help="patterns.json path to score read-only")
    parser.add_argument("--patterns", help="patterns.json path to score read-only")
    parser.add_argument("--fixture", help="fixture JSON path with input patterns and expected oracle")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    selected = [value for value in (args.path, args.patterns, args.fixture) if value]
    if len(selected) != 1:
        raise SystemExit("pass exactly one of positional path, --patterns <path>, or --fixture <path>")

    if args.fixture:
        return run_fixture(Path(args.fixture))

    path = Path(args.patterns or args.path)
    data = load_json(path)
    scored = score_patterns(extract_patterns(data), parse_now(data.get("now")))
    print(json.dumps(output_payload(scored), ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
