#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# skill-fog uninstaller
# ─────────────────────────────────────────────

CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills/skill-fog"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SKILL_FOG_DIR="$HOME/.skill-fog"
INSTALLED_CLI="$SKILL_FOG_DIR/bin/skill-fog"
LOCAL_BIN_LINK="$HOME/.local/bin/skill-fog"
HOME_BIN_LINK="$HOME/bin/skill-fog"
HOOK_CMD="bash $HOME/.skill-fog/hooks/stop.sh"
SESSION_START_HOOK_CMD="bash $HOME/.skill-fog/hooks/session-start.sh"
ASSUME_YES=0
DATA_ACTION="prompt"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[skill-fog]${NC} $*"; }
success() { echo -e "${GREEN}[skill-fog]${NC} $*"; }
warn()    { echo -e "${YELLOW}[skill-fog]${NC} $*"; }
error()   { echo -e "${RED}[skill-fog]${NC} $*"; }

usage() {
  cat <<EOF
Usage: uninstall.sh [options]

Uninstall skill-fog from the current HOME.

Options:
  --yes          Answer yes to confirmation prompts.
  --keep-data    Preserve ~/.skill-fog without prompting.
  --remove-data  Remove ~/.skill-fog without prompting.
  --help         Show this help message.
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes)
        ASSUME_YES=1
        ;;
      --keep-data)
        if [ "$DATA_ACTION" = "remove" ]; then
          error "--keep-data and --remove-data cannot be used together."
          exit 2
        fi
        DATA_ACTION="keep"
        ;;
      --remove-data)
        if [ "$DATA_ACTION" = "keep" ]; then
          error "--keep-data and --remove-data cannot be used together."
          exit 2
        fi
        DATA_ACTION="remove"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage
        exit 2
        ;;
    esac
    shift
  done
}

confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local yn

  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi

  if [ "$default" = "y" ]; then
    prompt="$prompt [Y/n] "
  else
    prompt="$prompt [y/N] "
  fi

  read -r -p "$prompt" yn
  yn="${yn:-$default}"
  case "$yn" in
    [Yy]*) return 0 ;;
    *)     return 1 ;;
  esac
}

# ─────────────────────────────────────────────
# 공통: settings.json에서 특정 훅 명령어 제거
# ─────────────────────────────────────────────
remove_hook_by_cmd() {
  local event="$1"
  local cmd="$2"
  local label="$3"

  if command -v jq &>/dev/null; then
    local tmp_file="${SETTINGS_FILE}.tmp"
    if ! jq \
      --arg event "$event" \
      --arg cmd "$cmd" \
      '
      if .hooks[$event] then
        .hooks[$event] = [
          .hooks[$event][]
          | .hooks = [ .hooks[]? | select(.command != $cmd) ]
          | select((.hooks | length) > 0)
        ]
        | if .hooks[$event] | length == 0 then del(.hooks[$event]) else . end
        | if (.hooks | length) == 0 then del(.hooks) else . end
      else . end
      ' \
      "$SETTINGS_FILE" > "$tmp_file" 2>/dev/null; then
      error "Failed to parse settings.json for $label removal."
      return 1
    fi
    mv "$tmp_file" "$SETTINGS_FILE"
    success "$label removed from settings.json"
  else
    SF_SETTINGS_FILE="$SETTINGS_FILE" SF_EVENT="$event" SF_CMD="$cmd" SF_LABEL="$label" \
    python3 - <<'PYEOF'
import json, sys, os

sf = os.environ['SF_SETTINGS_FILE']
event = os.environ['SF_EVENT']
cmd = os.environ['SF_CMD']
label = os.environ['SF_LABEL']

with open(sf) as f:
    settings = json.loads(f.read().strip() or '{}')

event_hooks = settings.get('hooks', {}).get(event, [])
new_hooks = []
for entry in event_hooks:
    filtered = [h for h in entry.get('hooks', []) if h.get('command') != cmd]
    if filtered:
        new_entry = dict(entry)
        new_entry['hooks'] = filtered
        new_hooks.append(new_entry)

if 'hooks' in settings and event in settings['hooks']:
    if new_hooks:
        settings['hooks'][event] = new_hooks
    else:
        del settings['hooks'][event]
    if not settings['hooks']:
        del settings['hooks']

with open(sf, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f'[skill-fog] {label} removed (python3)')
PYEOF
  fi
}

# ─────────────────────────────────────────────
# 1. settings.json에서 skill-fog 훅 제거
# ─────────────────────────────────────────────
remove_hook() {
  info "Removing skill-fog hooks from settings.json..."

  if [ ! -f "$SETTINGS_FILE" ]; then
    info "settings.json not found, skipping hook removal."
    return
  fi

  local backup_file="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$SETTINGS_FILE" "$backup_file"
  info "Backed up settings.json to: $backup_file"

  remove_hook_by_cmd "Stop" "$HOOK_CMD" "Stop hook"
  remove_hook_by_cmd "SessionStart" "$SESSION_START_HOOK_CMD" "SessionStart hook"

  # session-start.sh 파일 삭제
  if [ -f "$SKILL_FOG_DIR/hooks/session-start.sh" ]; then
    rm "$SKILL_FOG_DIR/hooks/session-start.sh"
    success "session-start.sh removed"
  fi
}

# ─────────────────────────────────────────────
# 2. ~/.claude/agents/ 에서 평가 에이전트 제거
# ─────────────────────────────────────────────
remove_agents() {
  info "Removing evaluator agents from ~/.claude/agents/..."

  local agents_dir="$CLAUDE_DIR/agents"
  local removed=0

  for agent_file in skill-evaluator.md agent-evaluator-v2.md; do
    local dest="$agents_dir/$agent_file"
    if [ -f "$dest" ]; then
      rm "$dest"
      success "Removed $dest"
      removed=$((removed + 1))
    fi
  done

  if [ "$removed" -eq 0 ]; then
    info "No evaluator agents found, skipping."
  fi
}

# ─────────────────────────────────────────────
# 3. ~/.claude/skills/skill-fog/ 삭제
# ─────────────────────────────────────────────
remove_skill() {
  info "Removing skill files..."

  if [ -d "$SKILLS_DIR" ]; then
    rm -rf "$SKILLS_DIR"
    success "Removed $SKILLS_DIR"
  else
    info "Skill directory not found, skipping."
  fi
}

# ─────────────────────────────────────────────
# 3. CLI 심볼릭 링크 제거
# ─────────────────────────────────────────────
remove_cli() {
  info "Removing CLI symlink(s)..."

  local removed=0
  local installed_cli="$INSTALLED_CLI"
  if [ -e "$installed_cli" ]; then
    installed_cli="$(cd -P "$(dirname "$installed_cli")" && pwd)/$(basename "$installed_cli")"
  fi

  resolve_symlink_target() {
    local link="$1"
    local target
    target="$(readlink "$link")"
    case "$target" in
      /*) ;;
      *) target="$(cd -P "$(dirname "$link")" && pwd)/$target" ;;
    esac
    if [ -e "$target" ]; then
      local target_dir
      target_dir="$(cd -P "$(dirname "$target")" && pwd)"
      echo "$target_dir/$(basename "$target")"
    else
      echo "$target"
    fi
  }

  for link in "$LOCAL_BIN_LINK" "$HOME_BIN_LINK"; do
    if [ -L "$link" ]; then
      local target
      target="$(resolve_symlink_target "$link")"
      if [ "$target" = "$installed_cli" ]; then
        rm "$link"
        success "Removed symlink: $link"
        removed=$((removed + 1))
      else
        warn "Symlink at $link points to $target, not $installed_cli; skipping."
      fi
    elif [ -f "$link" ]; then
      warn "Regular file at $link (not a symlink), skipping."
    fi
  done

  if [ "$removed" -eq 0 ]; then
    info "No CLI symlinks found."
  fi
}

# ─────────────────────────────────────────────
# 4. ~/.skill-fog/ 삭제 여부 확인
# ─────────────────────────────────────────────
remove_data() {
  if [ ! -d "$SKILL_FOG_DIR" ]; then
    info "~/.skill-fog/ not found, skipping."
    return
  fi

  echo ""
  warn "~/.skill-fog/ contains your pattern data and logs."
  warn "Deleting it will lose all collected patterns."
  echo ""

  if [ "$DATA_ACTION" = "keep" ]; then
    info "Keeping $SKILL_FOG_DIR (data preserved)."
    return
  fi

  if [ "$DATA_ACTION" = "remove" ] || confirm "Delete ~/.skill-fog/ and all pattern data?" "n"; then
    rm -rf "$SKILL_FOG_DIR"
    success "Removed $SKILL_FOG_DIR"
  else
    info "Keeping $SKILL_FOG_DIR (data preserved)."
    info "You can delete it manually later: rm -rf ~/.skill-fog"
  fi
}

# ─────────────────────────────────────────────
# 5. CLAUDE.md에서 skill-fog 블록 제거
# ─────────────────────────────────────────────
remove_claude_md() {
  local claude_md="$HOME/.claude/CLAUDE.md"
  local marker="# skill-fog: pattern detection"
  local old_marker="# skill-fog: 대화 중 반복 패턴 감지"

  if [ ! -f "$claude_md" ]; then
    info "CLAUDE.md not found, skipping."
    return
  fi

  if ! grep -q "$marker" "$claude_md" && ! grep -q "$old_marker" "$claude_md"; then
    info "skill-fog entry not found in CLAUDE.md, skipping."
    return
  fi

  # 백업 먼저
  local backup_file="${claude_md}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$claude_md" "$backup_file"
  info "Backed up CLAUDE.md to: $backup_file"

  # skill-fog 블록 제거 (구버전 한국어 / 신버전 영어 마커 둘 다)
  python3 - <<PYEOF
import re, os

claude_md = os.path.expanduser('$claude_md')

with open(claude_md, 'r', encoding='utf-8') as f:
    content = f.read()

# 빈 줄 + 마커 + 내용 줄(들) 패턴 제거 — 줄 수 변화에 유연하게 대응
for pat in (
    r'\n# skill-fog: pattern detection.*?(?=\n#|\Z)',
    r'\n# skill-fog: 대화 중 반복 패턴 감지.*?(?=\n#|\Z)',
):
    content = re.sub(pat, '', content, flags=re.DOTALL)

with open(claude_md, 'w', encoding='utf-8') as f:
    f.write(content)

print('[skill-fog] skill-fog entry removed from CLAUDE.md')
PYEOF

  success "skill-fog entry removed from CLAUDE.md"
}

# ─────────────────────────────────────────────
# 완료 메시지
# ─────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  skill-fog uninstalled successfully.${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  Restart Claude Code to deactivate the Stop hook."
  echo ""
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
main() {
  parse_args "$@"

  echo ""
  info "Starting skill-fog uninstallation..."
  echo ""

  remove_hook
  remove_agents
  remove_skill
  remove_cli
  remove_claude_md
  remove_data
  print_summary
}

main "$@"
