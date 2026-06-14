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

    # skill-fog 훅 명령어만 제거하고 같은 Stop 항목의 다른 훅은 보존
    if ! jq \
      --arg cmd "$HOOK_CMD" \
      '
      if .hooks.Stop then
        .hooks.Stop = [
          .hooks.Stop[]
          | .hooks = [ .hooks[]? | select(.command != $cmd) ]
          | select((.hooks | length) > 0)
        ]
        | if .hooks.Stop | length == 0 then del(.hooks.Stop) else . end
        | if (.hooks | length) == 0 then del(.hooks) else . end
      else . end
      ' \
      "$SETTINGS_FILE" > "$tmp_file" 2>/dev/null; then
      error "Failed to parse settings.json. Backup available at: $backup_file"
      return 1
    fi
    mv "$tmp_file" "$SETTINGS_FILE"

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
new_stop = []
for entry in stop_hooks:
    filtered_hooks = [
        h for h in entry.get('hooks', [])
        if h.get('command') != hook_cmd
    ]
    if filtered_hooks:
        new_entry = dict(entry)
        new_entry['hooks'] = filtered_hooks
        new_stop.append(new_entry)

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
  local marker="# skill-fog: 대화 중 반복 패턴 감지"

  if [ ! -f "$claude_md" ]; then
    info "CLAUDE.md not found, skipping."
    return
  fi

  if ! grep -q "$marker" "$claude_md"; then
    info "skill-fog entry not found in CLAUDE.md, skipping."
    return
  fi

  # 백업 먼저
  local backup_file="${claude_md}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$claude_md" "$backup_file"
  info "Backed up CLAUDE.md to: $backup_file"

  # skill-fog 블록 제거 (마커 줄부터 다음 빈 줄 이후까지 포함하는 2줄 블록)
  python3 - <<PYEOF
import re, os

claude_md = os.path.expanduser('$claude_md')

with open(claude_md, 'r', encoding='utf-8') as f:
    content = f.read()

# 빈 줄 + 마커 줄 + 다음 줄(내용) 패턴 제거
pattern = r'\n# skill-fog: 대화 중 반복 패턴 감지[^\n]*\n[^\n]*\n?'
new_content = re.sub(pattern, '', content)

with open(claude_md, 'w', encoding='utf-8') as f:
    f.write(new_content)

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
  remove_skill
  remove_cli
  remove_claude_md
  remove_data
  print_summary
}

main "$@"
