#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# skill-fog uninstaller
# ─────────────────────────────────────────────

CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills/skill-fog"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SKILL_FOG_DIR="$HOME/.skill-fog"
LOCAL_BIN_LINK="$HOME/.local/bin/skill-fog"
HOME_BIN_LINK="$HOME/bin/skill-fog"
HOOK_CMD="bash ~/.skill-fog/hooks/stop.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[skill-fog]${NC} $*"; }
success() { echo -e "${GREEN}[skill-fog]${NC} $*"; }
warn()    { echo -e "${YELLOW}[skill-fog]${NC} $*"; }
error()   { echo -e "${RED}[skill-fog]${NC} $*"; }

confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local yn

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
# 1. settings.json에서 skill-fog 훅 제거
# ─────────────────────────────────────────────
remove_hook() {
  info "Removing Stop hook from settings.json..."

  if [ ! -f "$SETTINGS_FILE" ]; then
    info "settings.json not found, skipping hook removal."
    return
  fi

  # 백업 먼저
  local backup_file="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$SETTINGS_FILE" "$backup_file"
  info "Backed up settings.json to: $backup_file"

  if command -v jq &>/dev/null; then
    local tmp_file="${SETTINGS_FILE}.tmp"

    # skill-fog 훅 명령어를 포함하는 항목만 제거
    jq \
      --arg cmd "$HOOK_CMD" \
      '
      if .hooks.Stop then
        .hooks.Stop = [
          .hooks.Stop[]
          | select(
              (.hooks | map(select(.command == $cmd)) | length) == 0
            )
        ]
        | if .hooks.Stop | length == 0 then del(.hooks.Stop) else . end
        | if (.hooks | length) == 0 then del(.hooks) else . end
      else . end
      ' \
      "$SETTINGS_FILE" > "$tmp_file" && mv "$tmp_file" "$SETTINGS_FILE"

    success "Stop hook removed from settings.json"

  else
    # python3 fallback
    python3 - <<PYEOF
import json, sys, os

settings_file = os.path.expanduser('$SETTINGS_FILE')
hook_cmd = '$HOOK_CMD'

with open(settings_file, 'r') as f:
    content = f.read().strip()
    settings = json.loads(content) if content else {}

stop_hooks = settings.get('hooks', {}).get('Stop', [])
new_stop = [
    entry for entry in stop_hooks
    if not any(h.get('command') == hook_cmd for h in entry.get('hooks', []))
]

if 'hooks' in settings and 'Stop' in settings['hooks']:
    if new_stop:
        settings['hooks']['Stop'] = new_stop
    else:
        del settings['hooks']['Stop']
    if not settings['hooks']:
        del settings['hooks']

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')

print('[skill-fog] Stop hook removed (python3)')
PYEOF
  fi
}

# ─────────────────────────────────────────────
# 2. ~/.claude/skills/skill-fog/ 삭제
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

  for link in "$LOCAL_BIN_LINK" "$HOME_BIN_LINK"; do
    if [ -L "$link" ]; then
      rm "$link"
      success "Removed symlink: $link"
      removed=$((removed + 1))
    elif [ -f "$link" ]; then
      warn "Regular file at $link (not a symlink). Removing..."
      rm "$link"
      removed=$((removed + 1))
    fi
  done

  [ "$removed" -eq 0 ] && info "No CLI symlinks found."
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

  if confirm "Delete ~/.skill-fog/ and all pattern data?" "n"; then
    rm -rf "$SKILL_FOG_DIR"
    success "Removed $SKILL_FOG_DIR"
  else
    info "Keeping $SKILL_FOG_DIR (data preserved)."
    info "You can delete it manually later: rm -rf ~/.skill-fog"
  fi
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
  echo ""
  info "Starting skill-fog uninstallation..."
  echo ""

  remove_hook
  remove_skill
  remove_cli
  remove_data
  print_summary
}

main "$@"
