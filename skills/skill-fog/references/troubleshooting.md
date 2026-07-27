# Troubleshooting Reference

Load this reference only when skill-fog behavior is missing, duplicated, corrupted, or when packaging/install validation fails.

## No pattern data
If `~/.skill-fog/patterns.json` cannot be read, treat the check as `NO_DATA` and do not show a proposal. Manual `/skill-fog` should print an empty pattern object:

```bash
cat ~/.skill-fog/patterns.json 2>/dev/null || echo '{"patterns":{}}'
```

## Duplicate proposal in the same session
Check `session_proposed` first:

- STEP A adds only pending pids actually proposed to the user in the current session.
- Accepted/rejected stale pending files deleted or skipped before proposal are not added.
- Threshold checks add the pid after `THRESHOLD_MET` is shown.
- Manual `/skill-fog` adds the selected active pid before entering STEP B.

If the pid is already present, do not ask again in that session.

## Pending file is stale
If a pending file points at a pattern whose status is `accepted` or `rejected`, delete the pending file and skip it. If status is `active` or missing, continue with the proposal.

## Broken or partial JSON
State writes should use a temporary file plus `os.replace`. If JSON is unreadable, avoid mutation and report that the local skill-fog state file must be repaired from valid JSON before state transitions can continue.

## Threshold never fires
Verify:

- The message has at least 10 characters before normalization.
- UUID replacement runs before number replacement.
- Normalized canonical text is not empty.
- The derived pid exists in `patterns.json`.
- `count >= 3`.
- `len(sessions) >= 2`.
- `status == active`.
- The pid is not already in `session_proposed`.

## Packaging
Runtime references required by `SKILL.md` must be included in `npm pack`. Validate with:

```bash
npm pack --dry-run --json
```

The packed file list should include `SKILL.md` and `references/*.md`. Benchmark docs and fixtures are not required at runtime unless a future `SKILL.md` explicitly references them.
