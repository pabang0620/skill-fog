#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# skill-fog installer
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FOG_DIR="$HOME/.skill-fog"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills/skill-fog"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
LOCAL_BIN="$HOME/.local/bin"
HOOK_CMD="bash $HOME/.skill-fog/hooks/stop.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[skill-fog]${NC} $*"; }
success() { echo -e "${GREEN}[skill-fog]${NC} $*"; }
warn()    { echo -e "${YELLOW}[skill-fog]${NC} $*"; }
error()   { echo -e "${RED}[skill-fog]${NC} $*"; }

CURRENT_STEP="init"
trap 'error "Installation failed at step: $CURRENT_STEP. Run ./uninstall.sh to clean up partial installation."; exit 1' ERR

# ─────────────────────────────────────────────
# 1. 의존성 확인
# ─────────────────────────────────────────────
check_dependencies() {
  CURRENT_STEP="check_dependencies"
  info "Checking dependencies..."

  if command -v jq &>/dev/null; then
    success "jq found: $(jq --version)"
  else
    warn "jq not found. Falling back to python3 for JSON processing."
    if command -v python3 &>/dev/null; then
      success "python3 found as fallback: $(python3 --version 2>&1)"
    else
      error "Neither jq nor python3 found!"
      error "Please install jq: https://stedolan.github.io/jq/download/"
      error "  macOS:  brew install jq"
      error "  Ubuntu: apt-get install jq"
      error "  Fedora: dnf install jq"
      exit 1
    fi
  fi
}

# ─────────────────────────────────────────────
# 2. 디렉토리 구조 생성
# ─────────────────────────────────────────────
create_directories() {
  CURRENT_STEP="create_directories"
  info "Creating ~/.skill-fog directory structure..."

  mkdir -p \
    "$SKILL_FOG_DIR/hooks" \
    "$SKILL_FOG_DIR/pending" \
    "$SKILL_FOG_DIR/logs"

  success "Directories created: $SKILL_FOG_DIR"
}

# ─────────────────────────────────────────────
# 3. patterns.json 초기화 (없는 경우만)
# ─────────────────────────────────────────────
init_patterns() {
  CURRENT_STEP="init_patterns"
  local patterns_file="$SKILL_FOG_DIR/patterns.json"
  if [ ! -f "$patterns_file" ]; then
    echo '{"patterns":{}}' > "$patterns_file"
    success "Initialized patterns.json"
  else
    info "patterns.json already exists, skipping."
  fi
}

# ─────────────────────────────────────────────
# 4. SKILL.md 복사
# ─────────────────────────────────────────────
install_skill() {
  CURRENT_STEP="install_skill"
  info "Installing SKILL.md to $SKILLS_DIR..."

  mkdir -p "$SKILLS_DIR"

  if [ -f "$SCRIPT_DIR/SKILL.md" ]; then
    cp "$SCRIPT_DIR/SKILL.md" "$SKILLS_DIR/SKILL.md"
    success "SKILL.md installed to $SKILLS_DIR/SKILL.md"
  else
    error "SKILL.md not found in $SCRIPT_DIR"
    exit 1
  fi
}

# ─────────────────────────────────────────────
# 5. hooks/stop.sh 복사
# ─────────────────────────────────────────────
install_hook() {
  CURRENT_STEP="install_hook"
  info "Installing stop hook..."

  if [ -f "$SCRIPT_DIR/hooks/stop.sh" ]; then
    cp "$SCRIPT_DIR/hooks/stop.sh" "$SKILL_FOG_DIR/hooks/stop.sh"
    chmod +x "$SKILL_FOG_DIR/hooks/stop.sh"
    success "stop.sh installed and made executable"
  else
    error "hooks/stop.sh not found in $SCRIPT_DIR/hooks/"
    exit 1
  fi
}

# ─────────────────────────────────────────────
# 6. CLI 심볼릭 링크 생성
# ─────────────────────────────────────────────
install_cli() {
  CURRENT_STEP="install_cli"
  info "Installing skill-fog CLI..."

  local cli_src="$SCRIPT_DIR/bin/skill-fog"
  local bin_dir=""

  if [ ! -f "$cli_src" ]; then
    error "bin/skill-fog not found in $SCRIPT_DIR/bin/"
    exit 1
  fi

  chmod +x "$cli_src"

  # ~/.local/bin 우선, 없으면 ~/bin
  if [ -d "$LOCAL_BIN" ] || mkdir -p "$LOCAL_BIN" 2>/dev/null; then
    bin_dir="$LOCAL_BIN"
  elif [ -d "$HOME/bin" ]; then
    bin_dir="$HOME/bin"
  else
    mkdir -p "$HOME/bin"
    bin_dir="$HOME/bin"
  fi

  local link_path="$bin_dir/skill-fog"

  # 기존 심볼릭 링크 제거 후 재생성 (멱등성)
  if [ -L "$link_path" ]; then
    rm "$link_path"
  elif [ -f "$link_path" ]; then
    warn "Regular file exists at $link_path, backing up..."
    mv "$link_path" "${link_path}.bak"
  fi

  ln -s "$cli_src" "$link_path"
  success "CLI linked: $link_path -> $cli_src"

  # PATH 확인
  if ! echo "$PATH" | grep -q "$bin_dir"; then
    warn "$bin_dir is not in your PATH."
    warn "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
    warn "  export PATH=\"\$PATH:$bin_dir\""
  fi
}

# ─────────────────────────────────────────────
# 7. settings.json 백업
# ─────────────────────────────────────────────
backup_settings() {
  CURRENT_STEP="backup_settings"
  if [ -f "$SETTINGS_FILE" ]; then
    local backup_file="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_FILE" "$backup_file"
    success "settings.json backed up to: $backup_file"
  else
    # settings.json이 없으면 빈 JSON으로 초기화
    mkdir -p "$CLAUDE_DIR"
    echo '{}' > "$SETTINGS_FILE"
    info "Created new settings.json"
  fi
}

# ─────────────────────────────────────────────
# 8. settings.json에 Stop 훅 등록
# ─────────────────────────────────────────────
register_hook() {
  CURRENT_STEP="register_hook"
  info "Registering Stop hook in settings.json..."

  # 중복 확인
  if command -v jq &>/dev/null; then
    local already_registered
    already_registered=$(jq -r \
      --arg cmd "$HOOK_CMD" \
      '.hooks.Stop[]?.hooks[]? | select(.command == $cmd) | .command' \
      "$SETTINGS_FILE" 2>/dev/null || echo "")

    if [ -n "$already_registered" ]; then
      info "Stop hook already registered, skipping."
      return
    fi

    # jq로 훅 추가 (기존 훅 보존)
    local tmp_file="${SETTINGS_FILE}.tmp"
    jq \
      --arg cmd "$HOOK_CMD" \
      '
      # hooks 키 없으면 생성
      .hooks //= {} |
      # Stop 키 없으면 빈 배열로
      .hooks.Stop //= [] |
      # 새 훅 항목 추가
      .hooks.Stop += [{
        "matcher": "",
        "hooks": [{
          "type": "command",
          "command": $cmd
        }]
      }]
      ' \
      "$SETTINGS_FILE" > "$tmp_file" && mv "$tmp_file" "$SETTINGS_FILE"

    success "Stop hook registered in settings.json"

  else
    # python3 fallback
    python3 - <<PYEOF
import json, sys, os

settings_file = os.path.expanduser('$SETTINGS_FILE')
hook_cmd = '$HOOK_CMD'

with open(settings_file, 'r') as f:
    content = f.read().strip()
    settings = json.loads(content) if content else {}

hooks = settings.setdefault('hooks', {})
stop_hooks = hooks.setdefault('Stop', [])

# 중복 확인
for entry in stop_hooks:
    for h in entry.get('hooks', []):
        if h.get('command') == hook_cmd:
            print('[skill-fog] Hook already registered (python3 check)')
            sys.exit(0)

stop_hooks.append({
    'matcher': '',
    'hooks': [{'type': 'command', 'command': hook_cmd}]
})

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')

print('[skill-fog] Stop hook registered (python3)')
PYEOF
  fi
}

# ─────────────────────────────────────────────
# 9. CLAUDE.md에 skill-fog 활성화 등록
# ─────────────────────────────────────────────
register_claude_md() {
  CURRENT_STEP="register_claude_md"
  local claude_md="$HOME/.claude/CLAUDE.md"
  local marker="# skill-fog: 대화 중 반복 패턴 감지"

  if [ -f "$claude_md" ] && grep -q "$marker" "$claude_md"; then
    info "CLAUDE.md already configured"
    return
  fi

  cat >> "$claude_md" << 'CLAUDEMD'

# skill-fog: 대화 중 반복 패턴 감지 및 스킬 자동 생성 (자동 로드)
skill-fog 스킬을 항상 활성 상태로 유지한다. 매 5번째 사용자 메시지마다 ~/.skill-fog/patterns.json을 확인하고 반복 패턴을 감지한다. 임계값(동일 패턴 3회 + 2개 이상 세션) 도달 시 즉시 사용자에게 skill / command / agent 생성을 제안한다.
CLAUDEMD

  success "skill-fog registered in CLAUDE.md"
}

# ─────────────────────────────────────────────
# 완료 메시지
# ─────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  skill-fog installed successfully!${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${BLUE}What's installed:${NC}"
  echo -e "    ~/.skill-fog/           Pattern storage directory"
  echo -e "    ~/.claude/skills/skill-fog/SKILL.md"
  echo -e "    ~/.skill-fog/hooks/stop.sh   (Stop hook)"
  echo -e "    ~/.local/bin/skill-fog       (CLI)"
  echo -e "    ~/.claude/CLAUDE.md          (skill-fog always-on entry)"
  echo ""
  echo -e "  ${BLUE}How it works:${NC}"
  echo -e "    1. Each Claude Code session end → stop.sh analyzes patterns"
  echo -e "    2. Pattern detected ≥3 times across ≥2 sessions → pending"
  echo -e "    3. Next session start → skill-fog suggests skill/command/agent"
  echo ""
  echo -e "  ${BLUE}CLI commands:${NC}"
  echo -e "    skill-fog status    Show pattern statistics"
  echo -e "    skill-fog review    Review and act on pending patterns"
  echo -e "    skill-fog list      List generated skills/commands/agents"
  echo -e "    skill-fog doctor    Diagnose installation"
  echo -e "    skill-fog clean     Remove old/rejected patterns"
  echo ""
  echo -e "  Restart Claude Code to activate the Stop hook."
  echo ""
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
main() {
  echo ""
  info "Starting skill-fog installation..."
  echo ""

  check_dependencies
  create_directories
  init_patterns
  install_skill
  install_hook
  install_cli
  backup_settings
  register_hook
  register_claude_md
  print_summary
}

main "$@"
