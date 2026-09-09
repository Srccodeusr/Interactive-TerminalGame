#!/usr/bin/env bash
# ============================================================================
#  _____                   _____                            _____
# |_   _|__ _ _ _ __      / ____|                          |  ___|
#   | |/ _ \ '_| '_ \    | |  __  __ _ _ __ ___   ___      | |__  __  __
#   | |  __/ |_| | | |   | | |_ |/ _` | '_ ` _ \ / _ \     |  __| \ \/ /
#   |_|\___|_(_|_| |_|   | |__| | (_| | | | | | |  __/     | |___  >  <
#                          \_____|\__,_|_| |_| |_|\___|     |_____|/_/\_\
#
#  TermGame Executer Script
#  Made by prime.dev1
#  Licensed under MIT + Attribution Requirement — see LICENSE.
#  If you fork or redistribute this, keep the "prime.dev1" credit
#  below and in this header intact.
#
#  Clones/updates a target repo, auto-detects its project type
#  (Node / Python / Rust / Make / plain bash entry script), installs
#  whatever dependencies that type needs, and runs it — all from one
#  numbered menu. Content-agnostic: it doesn't know or care what the
#  target project actually does, only how to build/run it.
# ============================================================================

set -uo pipefail

# ----------------------------------------------------------------------------
# Colors
# ----------------------------------------------------------------------------
RESET='\033[0m'
BOLD='\033[1m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD_CYAN='\033[1;36m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_RED='\033[1;31m'
BOLD_MAGENTA='\033[1;35m'
GRAY='\033[0;90m'

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
REPO_URL="https://github.com/Srccodeusr/Interactive-TerminalGame.git"
PROJECT_DIR="$HOME/interactive-terminalgame"
EXEC_HOME="$HOME/.termgame-executer"
LOG_DIR="$EXEC_HOME/logs"
STATE_DIR="$EXEC_HOME/state"
DETECTED_FILE="$STATE_DIR/detected_type"
CUSTOM_RUN_FILE="$STATE_DIR/custom_run_cmd"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
line() { printf "${GRAY}────────────────────────────────────────────────────────────${RESET}\n"; }

banner() {
  clear
  printf "${BOLD_CYAN}"
  cat <<'EOF'
  _____                   _____                            _____
 |_   _|__ _ _ _ __      / ____|                          |  ___|
   | |/ _ \ '_| '_ \    | |  __  __ _ _ __ ___   ___      | |__  __  __
   | |  __/ |_| | | |   | | |_ |/ _` | '_ ` _ \ / _ \     |  __| \ \/ /
   |_|\___|_(_|_| |_|   | |__| | (_| | | | | | |  __/     | |___  >  <
                          \_____|\__,_|_| |_| |_|\___|     |_____|/_/\_\
EOF
  printf "${RESET}"
  printf "${BOLD}${MAGENTA}          TermGame Executer Script${RESET}\n"
  printf "${GRAY}                Made by prime.dev1${RESET}\n"
  line
}

info()    { printf "${CYAN}➤ %s${RESET}\n" "$1"; }
success() { printf "${BOLD_GREEN}✔ %s${RESET}\n" "$1"; }
warn()    { printf "${BOLD_YELLOW}⚠ %s${RESET}\n" "$1"; }
error()   { printf "${BOLD_RED}✖ %s${RESET}\n" "$1"; }
step()    { printf "${BLUE}${BOLD}[STEP]${RESET} ${BOLD}%s${RESET}\n" "$1"; }

press_enter() {
  printf "\n${GRAY}Press Enter to return to the menu...${RESET}"
  read -r _
}

confirm() {
  local prompt="$1" reply
  printf "${YELLOW}%s [y/N]: ${RESET}" "$prompt"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

ensure_dirs() {
  mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true
}

pkg_install() {
  local pkgs=("$@")
  if command -v apt-get >/dev/null 2>&1; then
    if [[ $EUID -eq 0 ]]; then
      apt-get update -y >>"$LOG_DIR/apt.log" 2>&1
      apt-get install -y "${pkgs[@]}" >>"$LOG_DIR/apt.log" 2>&1
    elif command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -y >>"$LOG_DIR/apt.log" 2>&1
      sudo apt-get install -y "${pkgs[@]}" >>"$LOG_DIR/apt.log" 2>&1
    else
      warn "No root/sudo access — skipping apt-get for: ${pkgs[*]}"
      return 1
    fi
  else
    warn "apt-get not found on this system — skipping: ${pkgs[*]}"
    return 1
  fi
}

# ----------------------------------------------------------------------------
# 1) System dependency check (just the basics needed to clone anything)
# ----------------------------------------------------------------------------
check_system_deps() {
  step "Checking base dependencies (git, curl)"
  ensure_dirs
  local need_pkgs=()
  command -v git  >/dev/null 2>&1 || need_pkgs+=("git")
  command -v curl >/dev/null 2>&1 || need_pkgs+=("curl")

  if [[ ${#need_pkgs[@]} -gt 0 ]]; then
    info "Installing missing packages: ${need_pkgs[*]}"
    pkg_install "${need_pkgs[@]}" || warn "Some packages may not have installed — continuing anyway."
  else
    success "git, curl already present."
  fi

  command -v git >/dev/null 2>&1 || { error "git is required and could not be installed."; return 1; }
  return 0
}

# ----------------------------------------------------------------------------
# 2) Clone / Update the target repo
# ----------------------------------------------------------------------------
clone_or_update_repo() {
  step "Syncing repo from GitHub"
  ensure_dirs
  printf "  ${CYAN}%s${RESET}\n" "$REPO_URL"

  if [[ -d "$PROJECT_DIR/.git" ]]; then
    info "Existing checkout found at $PROJECT_DIR — pulling latest changes..."
    if git -C "$PROJECT_DIR" pull --ff-only 2>>"$LOG_DIR/git.log"; then
      success "Repository updated to the latest commit."
    else
      warn "Fast-forward pull failed (local changes or diverged history)."
      if confirm "Discard local changes and hard-reset to the latest remote version?"; then
        git -C "$PROJECT_DIR" fetch origin >>"$LOG_DIR/git.log" 2>&1
        local default_branch
        default_branch=$(git -C "$PROJECT_DIR" remote show origin 2>>"$LOG_DIR/git.log" | awk '/HEAD branch/ {print $NF}')
        default_branch=${default_branch:-main}
        git -C "$PROJECT_DIR" reset --hard "origin/$default_branch" >>"$LOG_DIR/git.log" 2>&1
        success "Repository force-updated to origin/$default_branch."
      else
        warn "Keeping existing local copy as-is."
      fi
    fi
  else
    info "No existing checkout — cloning fresh..."
    rm -rf "$PROJECT_DIR" 2>/dev/null || true
    if git clone "$REPO_URL" "$PROJECT_DIR" 2>>"$LOG_DIR/git.log"; then
      success "Clone complete → $PROJECT_DIR"
    else
      error "Git clone failed. Check $LOG_DIR/git.log for details."
      tail -n 20 "$LOG_DIR/git.log" 2>/dev/null
      return 1
    fi
  fi
  return 0
}

# ----------------------------------------------------------------------------
# 3) Auto-detect project type
# ----------------------------------------------------------------------------
detect_project_type() {
  local dir="$PROJECT_DIR"
  local found=()

  [[ -f "$dir/package.json" ]]        && found+=("node")
  [[ -f "$dir/requirements.txt" ]]    && found+=("python")
  [[ -f "$dir/pyproject.toml" ]]      && found+=("python")
  [[ -f "$dir/Cargo.toml" ]]          && found+=("rust")
  [[ -f "$dir/Makefile" ]]            && found+=("make")

  local bash_entry=""
  for c in run.sh start.sh main.sh game.sh play.sh; do
    [[ -f "$dir/$c" ]] && { bash_entry="$c"; break; }
  done
  [[ -n "$bash_entry" ]] && found+=("bash")

  local py_entry=""
  for c in main.py game.py app.py play.py; do
    [[ -f "$dir/$c" ]] && { py_entry="$c"; break; }
  done
  [[ -z "${found[*]:-}" && -n "$py_entry" ]] && found+=("python-script")

  local type="${found[0]:-unknown}"
  {
    echo "TYPE=$type"
    echo "BASH_ENTRY=$bash_entry"
    echo "PY_ENTRY=$py_entry"
  } > "$DETECTED_FILE"

  echo "$type"
}

show_detected_files() {
  local dir="$PROJECT_DIR"
  printf "${GRAY}Top-level files in %s:${RESET}\n" "$dir"
  ( cd "$dir" 2>/dev/null && ls -1 ) | sed 's/^/  /'
}

# ----------------------------------------------------------------------------
# 4) Install dependencies based on detected type
# ----------------------------------------------------------------------------
install_deps() {
  local type="$1"
  step "Installing dependencies for type: $type"

  case "$type" in
    node)
      command -v node >/dev/null 2>&1 || {
        warn "Node.js not found."
        if confirm "Install Node.js 20.x via NodeSource now?"; then
          curl -fsSL https://deb.nodesource.com/setup_20.x -o "$LOG_DIR/nodesource_setup.sh" 2>>"$LOG_DIR/apt.log"
          if [[ $EUID -eq 0 ]]; then
            bash "$LOG_DIR/nodesource_setup.sh" >>"$LOG_DIR/apt.log" 2>&1 && pkg_install nodejs
          elif command -v sudo >/dev/null 2>&1; then
            sudo bash "$LOG_DIR/nodesource_setup.sh" >>"$LOG_DIR/apt.log" 2>&1 && pkg_install nodejs
          else
            error "Cannot install Node.js without root/sudo. Install manually and re-run."
            return 1
          fi
        else
          error "Node.js is required for this project."
          return 1
        fi
      }
      ( cd "$PROJECT_DIR" && \
        if [[ -f pnpm-lock.yaml ]] && command -v pnpm >/dev/null 2>&1; then pnpm install
        elif [[ -f yarn.lock ]] && command -v yarn >/dev/null 2>&1; then yarn install
        else npm install
        fi
      ) 2>&1 | tee -a "$LOG_DIR/install.log"
      ;;
    python)
      command -v python3 >/dev/null 2>&1 || { pkg_install python3 python3-pip || true; }
      command -v pip3 >/dev/null 2>&1 || { pkg_install python3-pip || true; }
      if [[ -f "$PROJECT_DIR/requirements.txt" ]]; then
        ( cd "$PROJECT_DIR" && pip3 install -r requirements.txt --break-system-packages ) 2>&1 | tee -a "$LOG_DIR/install.log"
      elif [[ -f "$PROJECT_DIR/pyproject.toml" ]]; then
        ( cd "$PROJECT_DIR" && pip3 install . --break-system-packages ) 2>&1 | tee -a "$LOG_DIR/install.log"
      else
        info "No requirements.txt / pyproject.toml — nothing to install."
      fi
      ;;
    rust)
      command -v cargo >/dev/null 2>&1 || {
        error "cargo not found. Install Rust (https://rustup.rs) and re-run."
        return 1
      }
      ( cd "$PROJECT_DIR" && cargo build ) 2>&1 | tee -a "$LOG_DIR/install.log"
      ;;
    make)
      command -v make >/dev/null 2>&1 || pkg_install make || true
      ( cd "$PROJECT_DIR" && make ) 2>&1 | tee -a "$LOG_DIR/install.log"
      ;;
    bash|python-script)
      info "No build step needed for type '$type'."
      ;;
    *)
      warn "Unknown project type — nothing to install automatically."
      show_detected_files
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------------
# 5) Run the project based on detected type
# ----------------------------------------------------------------------------
run_project() {
  local type="$1" bash_entry="" py_entry=""
  [[ -f "$DETECTED_FILE" ]] && source "$DETECTED_FILE"

  step "Launching (type: $type)"
  info "Press Ctrl+C to stop and return to the menu."
  line

  case "$type" in
    node)
      if grep -q '"start"' "$PROJECT_DIR/package.json" 2>/dev/null; then
        ( cd "$PROJECT_DIR" && npm start ) 2>&1 | tee -a "$LOG_DIR/run.log"
      elif [[ -f "$PROJECT_DIR/index.js" ]]; then
        ( cd "$PROJECT_DIR" && node index.js ) 2>&1 | tee -a "$LOG_DIR/run.log"
      else
        error "No 'start' script in package.json and no index.js found."
        return 1
      fi
      ;;
    python)
      local entry="${PY_ENTRY:-}"
      if [[ -z "$entry" ]]; then
        for c in main.py game.py app.py play.py; do
          [[ -f "$PROJECT_DIR/$c" ]] && { entry="$c"; break; }
        done
      fi
      if [[ -z "$entry" ]]; then
        error "No recognizable Python entry point (main.py / game.py / app.py / play.py)."
        show_detected_files
        return 1
      fi
      ( cd "$PROJECT_DIR" && python3 "$entry" ) 2>&1 | tee -a "$LOG_DIR/run.log"
      ;;
    python-script)
      local entry="${PY_ENTRY:-}"
      [[ -z "$entry" ]] && { error "No Python entry point detected."; return 1; }
      ( cd "$PROJECT_DIR" && python3 "$entry" ) 2>&1 | tee -a "$LOG_DIR/run.log"
      ;;
    rust)
      ( cd "$PROJECT_DIR" && cargo run ) 2>&1 | tee -a "$LOG_DIR/run.log"
      ;;
    make)
      if ( cd "$PROJECT_DIR" && grep -qE '^run:' Makefile 2>/dev/null ); then
        ( cd "$PROJECT_DIR" && make run ) 2>&1 | tee -a "$LOG_DIR/run.log"
      else
        warn "No 'run' target in Makefile — built only. Check $PROJECT_DIR for the output binary."
      fi
      ;;
    bash)
      local entry="${BASH_ENTRY:-}"
      if [[ -z "$entry" ]]; then
        for c in run.sh start.sh main.sh game.sh play.sh; do
          [[ -f "$PROJECT_DIR/$c" ]] && { entry="$c"; break; }
        done
      fi
      if [[ -z "$entry" ]]; then
        error "No recognizable bash entry point found."
        show_detected_files
        return 1
      fi
      chmod +x "$PROJECT_DIR/$entry" 2>/dev/null || true
      ( cd "$PROJECT_DIR" && bash "./$entry" ) 2>&1 | tee -a "$LOG_DIR/run.log"
      ;;
    *)
      if [[ -f "$CUSTOM_RUN_FILE" ]]; then
        local cmd; cmd=$(cat "$CUSTOM_RUN_FILE")
        info "Using custom run command: $cmd"
        ( cd "$PROJECT_DIR" && eval "$cmd" ) 2>&1 | tee -a "$LOG_DIR/run.log"
      else
        error "Could not auto-detect how to run this project."
        show_detected_files
        info "Use menu option 5 to set a custom run command manually."
        return 1
      fi
      ;;
  esac

  warn "Process stopped."
  return 0
}

# ----------------------------------------------------------------------------
# Menu action: Install / Update
# ----------------------------------------------------------------------------
action_install_update() {
  banner
  check_system_deps || { press_enter; return 1; }
  clone_or_update_repo || { press_enter; return 1; }
  local type; type=$(detect_project_type)
  step "Detected project type: $type"
  show_detected_files
  install_deps "$type"
  success "Install/update step finished."
  press_enter
}

# ----------------------------------------------------------------------------
# Menu action: Play
# ----------------------------------------------------------------------------
action_play() {
  banner
  if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    warn "Project not cloned yet — run 'Install / Update' first."
    press_enter
    return 1
  fi
  local type
  if [[ -f "$DETECTED_FILE" ]]; then
    type=$(grep '^TYPE=' "$DETECTED_FILE" | cut -d= -f2)
  else
    type=$(detect_project_type)
  fi
  run_project "$type"
  press_enter
}

# ----------------------------------------------------------------------------
# Menu action: Re-detect
# ----------------------------------------------------------------------------
action_redetect() {
  banner
  step "Re-detecting project type"
  local type; type=$(detect_project_type)
  success "Detected type: $type"
  show_detected_files
  press_enter
}

# ----------------------------------------------------------------------------
# Menu action: View logs
# ----------------------------------------------------------------------------
action_view_logs() {
  banner
  step "Recent Logs"
  ensure_dirs
  local any=0
  for f in "$LOG_DIR/git.log" "$LOG_DIR/install.log" "$LOG_DIR/run.log" "$LOG_DIR/apt.log"; do
    if [[ -f "$f" ]]; then
      any=1
      printf "${BOLD_CYAN}── %s ──${RESET}\n" "$(basename "$f")"
      tail -n 12 "$f"
      echo
    fi
  done
  [[ $any -eq 0 ]] && warn "No logs yet."
  press_enter
}

# ----------------------------------------------------------------------------
# Menu action: Set custom run command (manual override)
# ----------------------------------------------------------------------------
action_set_custom_run() {
  banner
  step "Custom Run Command"
  ensure_dirs
  [[ -f "$CUSTOM_RUN_FILE" ]] && printf "${GRAY}Current: %s${RESET}\n" "$(cat "$CUSTOM_RUN_FILE")"
  printf "${CYAN}Enter the command to run from inside %s (blank to cancel):${RESET}\n" "$PROJECT_DIR"
  read -r cmd
  if [[ -n "$cmd" ]]; then
    echo "$cmd" > "$CUSTOM_RUN_FILE"
    success "Saved. This will be used whenever auto-detection can't determine how to run the project."
  else
    info "No change made."
  fi
  press_enter
}

# ----------------------------------------------------------------------------
# Main Menu
# ----------------------------------------------------------------------------
main_menu() {
  while true; do
    banner
    printf "${BOLD}Repository:${RESET} ${GRAY}%s${RESET}\n" "$REPO_URL"
    printf "${BOLD}Project dir:${RESET} ${GRAY}%s${RESET}\n\n" "$PROJECT_DIR"

    printf "  ${BOLD_GREEN}1)${RESET} Install / Update ${GRAY}— clone or pull, detect type, install deps${RESET}\n"
    printf "  ${BOLD_GREEN}2)${RESET} Play             ${GRAY}— run using the detected/last-known type${RESET}\n"
    printf "  ${BOLD_YELLOW}3)${RESET} Re-detect Project Type\n"
    printf "  ${CYAN}4)${RESET} View Logs\n"
    printf "  ${CYAN}5)${RESET} Set Custom Run Command\n"
    printf "  ${BOLD_RED}0)${RESET} Exit\n\n"
    line
    printf "${YELLOW}Select an option [0-5]: ${RESET}"
    read -r choice

    case "$choice" in
      1) action_install_update ;;
      2) action_play ;;
      3) action_redetect ;;
      4) action_view_logs ;;
      5) action_set_custom_run ;;
      0)
        banner
        printf "${BOLD_MAGENTA}Goodbye from TermGame Executer Script.${RESET}\n"
        printf "${GRAY}Made by prime.dev1${RESET}\n\n"
        exit 0
        ;;
      *) warn "Invalid selection: '$choice'"; sleep 1 ;;
    esac
  done
}

# ----------------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------------
ensure_dirs
main_menu
