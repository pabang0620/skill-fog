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

same_path() {
  [ "$(cd -P "$(dirname "$1")" && pwd)/$(basename "$1")" = "$(cd -P "$(dirname "$2")" && pwd)/$(basename "$2")" ]
}

copy_file_if_needed() {
  local src="$1"
  local dest="$2"
  if [ -e "$dest" ] && same_path "$src" "$dest"; then
    return 0
  fi
  cp "$src" "$dest"
}

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
    "$SKILL_FOG_DIR/bin" \
    "$SKILL_FOG_DIR/hooks" \
    "$SKILL_FOG_DIR/references" \
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
# 4. SKILL.md 및 references/ 복사
# ─────────────────────────────────────────────
install_skill() {
  CURRENT_STEP="install_skill"
  info "Installing SKILL.md and references/ to $SKILLS_DIR..."

  mkdir -p "$SKILLS_DIR"

  if [ -f "$SCRIPT_DIR/SKILL.md" ]; then
    cp "$SCRIPT_DIR/SKILL.md" "$SKILLS_DIR/SKILL.md"
    success "SKILL.md installed to $SKILLS_DIR/SKILL.md"
  else
    error "SKILL.md not found in $SCRIPT_DIR"
    exit 1
  fi

  if [ -d "$SCRIPT_DIR/references" ]; then
    rm -rf "$SKILLS_DIR/references"
    cp -R "$SCRIPT_DIR/references" "$SKILLS_DIR/references"
    success "references/ installed to $SKILLS_DIR/references"
  else
    error "references/ not found in $SCRIPT_DIR"
    exit 1
  fi
}

# ─────────────────────────────────────────────
# 5. 평가 에이전트 설치 (skill-evaluator, agent-evaluator-v2)
# ─────────────────────────────────────────────
install_agents() {
  CURRENT_STEP="install_agents"
  local agents_dir="$CLAUDE_DIR/agents"
  info "Installing evaluator agents to $agents_dir..."

  mkdir -p "$agents_dir"

  for agent_file in skill-evaluator.md agent-evaluator-v2.md; do
    if [ -f "$SCRIPT_DIR/agents/$agent_file" ]; then
      local dest="$agents_dir/$agent_file"
      if [ -f "$dest" ]; then
        info "$agent_file already exists at $dest, skipping."
      else
        cp "$SCRIPT_DIR/agents/$agent_file" "$dest"
        success "$agent_file installed to $dest"
      fi
    else
      warn "agents/$agent_file not found in $SCRIPT_DIR/agents/ — skipping"
    fi
  done
}

# ─────────────────────────────────────────────
# 6. hooks/stop.sh 복사
# ─────────────────────────────────────────────
install_hook() {
  CURRENT_STEP="install_hook"
  info "Installing hooks..."

  if [ -f "$SCRIPT_DIR/hooks/stop.sh" ]; then
    copy_file_if_needed "$SCRIPT_DIR/hooks/stop.sh" "$SKILL_FOG_DIR/hooks/stop.sh"
    chmod +x "$SKILL_FOG_DIR/hooks/stop.sh"
    success "stop.sh installed and made executable"
  else
    error "hooks/stop.sh not found in $SCRIPT_DIR/hooks/"
    exit 1
  fi

  if [ -f "$SCRIPT_DIR/hooks/session-start.sh" ]; then
    copy_file_if_needed "$SCRIPT_DIR/hooks/session-start.sh" "$SKILL_FOG_DIR/hooks/session-start.sh"
    chmod +x "$SKILL_FOG_DIR/hooks/session-start.sh"
    success "session-start.sh installed and made executable"
  else
    error "hooks/session-start.sh not found in $SCRIPT_DIR/hooks/"
    exit 1
  fi
}

# ─────────────────────────────────────────────
# 6. 설치된 CLI 런타임 번들 복사
# ─────────────────────────────────────────────
install_runtime_bundle() {
  CURRENT_STEP="install_runtime_bundle"
  info "Installing CLI runtime bundle to $SKILL_FOG_DIR..."

  local required_file
  for required_file in install.sh uninstall.sh SKILL.md; do
    if [ -f "$SCRIPT_DIR/$required_file" ]; then
      copy_file_if_needed "$SCRIPT_DIR/$required_file" "$SKILL_FOG_DIR/$required_file"
    else
      error "$required_file not found in $SCRIPT_DIR"
      exit 1
    fi
  done

  chmod +x "$SKILL_FOG_DIR/install.sh" "$SKILL_FOG_DIR/uninstall.sh"

  if [ -d "$SCRIPT_DIR/references" ]; then
    if ! same_path "$SCRIPT_DIR/references" "$SKILL_FOG_DIR/references"; then
      rm -rf "$SKILL_FOG_DIR/references"
      cp -R "$SCRIPT_DIR/references" "$SKILL_FOG_DIR/references"
    fi
  else
    error "references/ not found in $SCRIPT_DIR"
    exit 1
  fi

  if [ -f "$SCRIPT_DIR/package.json" ]; then
    copy_file_if_needed "$SCRIPT_DIR/package.json" "$SKILL_FOG_DIR/package.json"
  fi

  success "Runtime bundle installed"
}

# ─────────────────────────────────────────────
# 7. CLI 심볼릭 링크 생성
# ─────────────────────────────────────────────
install_cli() {
  CURRENT_STEP="install_cli"
  info "Installing skill-fog CLI..."

  local cli_src="$SCRIPT_DIR/bin/skill-fog"
  local installed_cli="$SKILL_FOG_DIR/bin/skill-fog"
  local bin_dir=""

  if [ ! -f "$cli_src" ]; then
    error "bin/skill-fog not found in $SCRIPT_DIR/bin/"
    exit 1
  fi

  chmod +x "$cli_src"
  copy_file_if_needed "$cli_src" "$installed_cli"
  chmod +x "$installed_cli"
  cli_src="$(cd -P "$(dirname "$cli_src")" && pwd)/$(basename "$cli_src")"
  installed_cli="$(cd -P "$(dirname "$installed_cli")" && pwd)/$(basename "$installed_cli")"

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

  # 기존 심볼릭 링크는 이 installer가 관리하는 대상일 때만 교체한다.
  if [ -L "$link_path" ]; then
    local target
    target="$(resolve_symlink_target "$link_path")"
    if [ "$target" = "$installed_cli" ] || [ "$target" = "$cli_src" ]; then
      rm "$link_path"
    else
      warn "Existing symlink at $link_path points to $target; leaving it unchanged."
      warn "CLI copy installed at $installed_cli, but PATH link was not changed."
      return 0
    fi
  elif [ -e "$link_path" ]; then
    warn "Existing non-symlink at $link_path; leaving it unchanged."
    warn "CLI copy installed at $installed_cli, but PATH link was not changed."
    return 0
  fi

  ln -s "$installed_cli" "$link_path"
  success "CLI linked: $link_path -> $installed_cli"

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
# 공통: settings.json에 훅 등록 (중복 방지, jq/python3 fallback)
# ─────────────────────────────────────────────
register_single_hook() {
  local event="$1"   # Stop, SessionStart 등
  local cmd="$2"     # 실행할 훅 명령어
  local label="$3"   # 로그용 이름

  if command -v jq &>/dev/null; then
    local already
    already=$(jq -r \
      --arg cmd "$cmd" \
      --arg event "$event" \
      '.hooks[$event][]?.hooks[]? | select(.command == $cmd) | .command' \
      "$SETTINGS_FILE" 2>/dev/null || echo "")

    if [ -n "$already" ]; then
      info "$label already registered, skipping."
      return
    fi

    local tmp_file="${SETTINGS_FILE}.tmp"
    jq \
      --arg event "$event" \
      --arg cmd "$cmd" \
      '
      .hooks //= {} |
      .hooks[$event] //= [] |
      .hooks[$event] += [{"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}]
      ' \
      "$SETTINGS_FILE" > "$tmp_file" && mv "$tmp_file" "$SETTINGS_FILE"

    success "$label registered in settings.json"

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

hooks = settings.setdefault('hooks', {})
event_hooks = hooks.setdefault(event, [])

for entry in event_hooks:
    for h in entry.get('hooks', []):
        if h.get('command') == cmd:
            print(f'[skill-fog] {label} already registered (python3 check)')
            sys.exit(0)

event_hooks.append({'matcher': '', 'hooks': [{'type': 'command', 'command': cmd}]})

with open(sf, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f'[skill-fog] {label} registered (python3)')
PYEOF
  fi
}

# ─────────────────────────────────────────────
# 8. settings.json에 훅 등록
# ─────────────────────────────────────────────
register_hook() {
  CURRENT_STEP="register_hook"
  info "Registering hooks in settings.json..."

  register_single_hook "Stop" "$HOOK_CMD" "Stop hook"
  register_single_hook "SessionStart" "bash $HOME/.skill-fog/hooks/session-start.sh" "SessionStart hook"
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
skill-fog 스킬을 항상 활성 상태로 유지한다. system-reminder에 "[skill-fog]" 텍스트가 포함된 경우, 사용자 메시지가 무엇이든 관계없이 반드시 첫 번째 응답으로 STEP A를 실행하여 패턴을 제안한다. 사용자가 "안녕" 같은 무관한 메시지를 보내도 skill-fog 제안이 먼저다. /skill-fog 수동 호출 시에도 동일하게 동작한다.
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
  echo -e "    ~/.claude/skills/skill-fog/references/"
  echo -e "    ~/.claude/agents/skill-evaluator.md"
  echo -e "    ~/.claude/agents/agent-evaluator-v2.md"
  echo -e "    ~/.skill-fog/hooks/stop.sh   (Stop hook)"
  echo -e "    ~/.skill-fog/install.sh      (Installed self-test source)"
  echo -e "    ~/.skill-fog/uninstall.sh    (Uninstaller)"
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
  install_agents
  install_hook
  install_runtime_bundle
  install_cli
  backup_settings
  register_hook
  register_claude_md
  print_summary
}

main "$@"
