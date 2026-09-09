#!/usr/bin/env bash
# ============================================================================
#   ____          _
#  / ___|__ _ ___| |_ ___  _ __ ___
# | |   / _` / __| __/ _ \| '_ ` _ \
# | |__| (_| \__ \ || (_) | | | | | |
#  \____\__,_|___/\__\___/|_| |_| |_|
#
#  Custom Prompt Game Engine
#  Made by prime.dev1
#  Licensed under MIT + Attribution Requirement — see LICENSE.
#  If you fork or redistribute this, keep the "prime.dev1" credit
#  below and in this header intact.
#
#  A menu-driven bash game engine. It does NOT ship with any content —
#  you supply your own entries as .variant files under variants/<theme>/.
#  A "prompt" (config/prompt.txt) tells the engine which theme/intensity/
#  rounds/speed to use for a session, plus a title+description shown as
#  the session banner. The engine only handles selection, no-repeat
#  shuffling, and rendering — it never generates content itself.
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
# Paths
# ----------------------------------------------------------------------------
GAME_HOME="$HOME/.customgame"
CONFIG_DIR="$GAME_HOME/config"
PROMPT_FILE="$CONFIG_DIR/prompt.txt"
VARIANTS_DIR="$GAME_HOME/variants"
STATE_DIR="$GAME_HOME/state"
LOG_DIR="$GAME_HOME/logs"
HISTORY_LOG="$LOG_DIR/history.log"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
line() { printf "${GRAY}────────────────────────────────────────────────────────────${RESET}\n"; }

banner() {
  clear
  printf "${BOLD_CYAN}"
  cat <<'EOF'
  ____          _
 / ___|__ _ ___| |_ ___  _ __ ___
| |   / _` / __| __/ _ \| '_ ` _ \
| |__| (_| \__ \ || (_) | | | | | |
 \____\__,_|___/\__\___/|_| |_| |_|
EOF
  printf "${RESET}"
  printf "${BOLD}${MAGENTA}          Custom Prompt Game Engine${RESET}\n"
  printf "${GRAY}                Made by prime.dev1${RESET}\n"
  line
}

info()    { printf "${CYAN}➤ %s${RESET}\n" "$1"; }
success() { printf "${BOLD_GREEN}✔ %s${RESET}\n" "$1"; }
warn()    { printf "${BOLD_YELLOW}⚠ %s${RESET}\n" "$1"; }
error()   { printf "${BOLD_RED}✖ %s${RESET}\n" "$1"; }
step()    { printf "${BLUE}${BOLD}[STEP]${RESET} ${BOLD}%s${RESET}\n" "$1"; }

press_enter() {
  printf "\n${GRAY}Press Enter to continue...${RESET}"
  read -r _
}

confirm() {
  local prompt="$1" reply
  printf "${YELLOW}%s [y/N]: ${RESET}" "$prompt"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

ensure_dirs() {
  mkdir -p "$CONFIG_DIR" "$VARIANTS_DIR" "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
}

# ----------------------------------------------------------------------------
# First-run seed: creates one demo theme with neutral placeholder entries
# so the engine is runnable/testable before you add your own content.
# ----------------------------------------------------------------------------
seed_demo_theme_if_empty() {
  if [[ -z "$(find "$VARIANTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]]; then
    mkdir -p "$VARIANTS_DIR/demo"
    cat > "$VARIANTS_DIR/demo/001.variant" <<'EOF'
ID=001
TITLE=Placeholder Entry One
INTENSITY=low
DESC<<END
This is a placeholder entry. Replace this text (and the ASCII block
below) with your own content, following this file's format.
END
ASCII<<END
   *
  ***
 *****
  ***
   *
END
EOF
    cat > "$VARIANTS_DIR/demo/002.variant" <<'EOF'
ID=002
TITLE=Placeholder Entry Two
INTENSITY=medium
DESC<<END
Another placeholder. Each .variant file is one entry in the pool that
the shuffle-bag selector draws from.
END
ASCII<<END
  /\_/\
 ( o.o )
  > ^ <
END
EOF
    cat > "$VARIANTS_DIR/demo/003.variant" <<'EOF'
ID=003
TITLE=Placeholder Entry Three
INTENSITY=high
DESC<<END
Third placeholder, tagged at a different intensity so you can see the
INTENSITY filter working when a prompt requests something other than
"any".
END
ASCII<<END
 [ ] [ ] [ ]
 [ ] [X] [ ]
 [ ] [ ] [ ]
END
EOF
  fi
}

# ----------------------------------------------------------------------------
# Prompt config (config/prompt.txt) — KEY=VALUE lines, plus KEY<<END ... END
# blocks for multi-line fields (DESC).
# ----------------------------------------------------------------------------
declare -A PROMPT

default_prompt_values() {
  PROMPT=()
  PROMPT[TITLE]="Untitled Session"
  PROMPT[DESC]="No description set."
  PROMPT[THEME]="demo"
  PROMPT[INTENSITY]="any"
  PROMPT[ROUNDS]="10"
  PROMPT[SPEED]="normal"
}

load_prompt() {
  default_prompt_values
  [[ -f "$PROMPT_FILE" ]] || return 0

  local in_block="" block_buf="" line_in key value
  while IFS= read -r line_in || [[ -n "$line_in" ]]; do
    if [[ -n "$in_block" ]]; then
      if [[ "$line_in" == "END" ]]; then
        PROMPT["$in_block"]="$block_buf"
        in_block=""
        block_buf=""
      else
        block_buf+="${line_in}"$'\n'
      fi
      continue
    fi
    [[ "$line_in" =~ ^[[:space:]]*#.*$ ]] && continue
    [[ -z "${line_in//[[:space:]]/}" ]] && continue
    if [[ "$line_in" =~ ^([A-Z_]+)\<\<END$ ]]; then
      in_block="${BASH_REMATCH[1]}"
      block_buf=""
      continue
    fi
    if [[ "$line_in" =~ ^([A-Z_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
      PROMPT["$key"]="$value"
    fi
  done < "$PROMPT_FILE"
}

write_prompt_file() {
  ensure_dirs
  {
    echo "# Custom Prompt Game Engine — session config"
    echo "# Edit by hand, or use the wizard from the menu."
    echo "TITLE=${PROMPT[TITLE]}"
    echo "THEME=${PROMPT[THEME]}"
    echo "INTENSITY=${PROMPT[INTENSITY]}"
    echo "ROUNDS=${PROMPT[ROUNDS]}"
    echo "SPEED=${PROMPT[SPEED]}"
    echo "DESC<<END"
    local desc="${PROMPT[DESC]}"
    desc="${desc%$'\n'}"   # avoid double newline if it already ends in one
    printf '%s\n' "$desc"
    echo "END"
  } > "$PROMPT_FILE"
}

list_themes() {
  find "$VARIANTS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

pick_theme_interactive() {
  local themes=() i=1
  while IFS= read -r t; do themes+=("$t"); done < <(list_themes)
  if [[ ${#themes[@]} -eq 0 ]]; then
    error "No themes found under $VARIANTS_DIR — create at least one folder with .variant files."
    return 1
  fi
  printf "${BOLD}Available themes:${RESET}\n"
  for t in "${themes[@]}"; do
    local cnt
    cnt=$(find "$VARIANTS_DIR/$t" -maxdepth 1 -name '*.variant' 2>/dev/null | wc -l | tr -d ' ')
    printf "  ${BOLD_CYAN}%d)${RESET} %s ${GRAY}(%s entries)${RESET}\n" "$i" "$t" "$cnt"
    i=$((i+1))
  done
  printf "${YELLOW}Choose a theme: ${RESET}"
  read -r sel
  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#themes[@]} )); then
    echo "${themes[$((sel-1))]}"
    return 0
  fi
  return 1
}

read_multiline() {
  # Reads lines until a lone "." — used by the wizard for DESC.
  local buf="" l
  while IFS= read -r l; do
    [[ "$l" == "." ]] && break
    buf+="${l}"$'\n'
  done
  printf '%s' "$buf"
}

prompt_wizard() {
  banner
  step "Custom Prompt — Guided Setup"
  load_prompt

  printf "${CYAN}Session title [%s]: ${RESET}" "${PROMPT[TITLE]}"
  read -r v; [[ -n "$v" ]] && PROMPT[TITLE]="$v"

  echo
  printf "${CYAN}Session description — type freely, end with a single '.' on its own line:${RESET}\n"
  local desc
  desc=$(read_multiline)
  [[ -n "${desc//[[:space:]]/}" ]] && PROMPT[DESC]="$desc"

  echo
  local theme
  if theme=$(pick_theme_interactive); then
    PROMPT[THEME]="$theme"
  else
    warn "Keeping current theme: ${PROMPT[THEME]}"
  fi

  echo
  printf "${CYAN}Intensity filter (any/low/medium/high) [%s]: ${RESET}" "${PROMPT[INTENSITY]}"
  read -r v; [[ -n "$v" ]] && PROMPT[INTENSITY]="$v"

  echo
  printf "${CYAN}Rounds per session, 0 = until you quit [%s]: ${RESET}" "${PROMPT[ROUNDS]}"
  read -r v; [[ -n "$v" ]] && PROMPT[ROUNDS]="$v"

  echo
  printf "${CYAN}Display speed (normal/typewriter) [%s]: ${RESET}" "${PROMPT[SPEED]}"
  read -r v; [[ -n "$v" ]] && PROMPT[SPEED]="$v"

  write_prompt_file
  success "Saved to $PROMPT_FILE"
  press_enter
}

edit_prompt_raw() {
  ensure_dirs
  [[ -f "$PROMPT_FILE" ]] || { default_prompt_values; write_prompt_file; }

  local editor="${EDITOR:-}"
  if [[ -z "$editor" ]]; then
    for c in nano vim vi; do
      command -v "$c" >/dev/null 2>&1 && { editor="$c"; break; }
    done
  fi
  if [[ -z "$editor" ]]; then
    error "No editor found. Set \$EDITOR, or install nano/vim, or use the guided wizard instead."
    press_enter
    return 1
  fi
  "$editor" "$PROMPT_FILE"
}

view_prompt() {
  banner
  step "Current Prompt Config"
  load_prompt
  printf "${BOLD}Title:${RESET}     %s\n" "${PROMPT[TITLE]}"
  printf "${BOLD}Theme:${RESET}     %s\n" "${PROMPT[THEME]}"
  printf "${BOLD}Intensity:${RESET} %s\n" "${PROMPT[INTENSITY]}"
  printf "${BOLD}Rounds:${RESET}    %s\n" "${PROMPT[ROUNDS]}"
  printf "${BOLD}Speed:${RESET}     %s\n" "${PROMPT[SPEED]}"
  echo
  printf "${BOLD}Description:${RESET}\n${GRAY}%s${RESET}\n" "${PROMPT[DESC]}"
  press_enter
}

custom_prompt_menu() {
  while true; do
    banner
    step "Custom Prompt Mode"
    printf "  ${BOLD_GREEN}1)${RESET} View current prompt\n"
    printf "  ${BOLD_GREEN}2)${RESET} Guided setup (answer a few questions)\n"
    printf "  ${BOLD_YELLOW}3)${RESET} Edit raw prompt.txt in a text editor\n"
    printf "  ${BOLD_CYAN}4)${RESET} Start game with this prompt\n"
    printf "  ${BOLD_RED}0)${RESET} Back to main menu\n\n"
    line
    printf "${YELLOW}Select an option [0-4]: ${RESET}"
    read -r c
    case "$c" in
      1) view_prompt ;;
      2) prompt_wizard ;;
      3) edit_prompt_raw ;;
      4) run_game ;;
      0) return 0 ;;
      *) warn "Invalid selection."; sleep 1 ;;
    esac
  done
}

# ----------------------------------------------------------------------------
# Variant file parsing — same KEY=VALUE / KEY<<END block format as prompt.txt
# ----------------------------------------------------------------------------
V_ID="" V_TITLE="" V_INTENSITY="" V_DESC="" V_ASCII=""

parse_variant_file() {
  local path="$1"
  V_ID="" V_TITLE="" V_INTENSITY="any" V_DESC="" V_ASCII=""
  local in_block="" block_buf="" line_in key value

  while IFS= read -r line_in || [[ -n "$line_in" ]]; do
    if [[ -n "$in_block" ]]; then
      if [[ "$line_in" == "END" ]]; then
        case "$in_block" in
          DESC)  V_DESC="$block_buf" ;;
          ASCII) V_ASCII="$block_buf" ;;
        esac
        in_block=""
        block_buf=""
      else
        block_buf+="${line_in}"$'\n'
      fi
      continue
    fi
    [[ "$line_in" =~ ^[[:space:]]*#.*$ ]] && continue
    [[ -z "${line_in//[[:space:]]/}" ]] && continue
    if [[ "$line_in" =~ ^([A-Z_]+)\<\<END$ ]]; then
      in_block="${BASH_REMATCH[1]}"
      block_buf=""
      continue
    fi
    if [[ "$line_in" =~ ^([A-Z_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
      case "$key" in
        ID)        V_ID="$value" ;;
        TITLE)     V_TITLE="$value" ;;
        INTENSITY) V_INTENSITY="$value" ;;
      esac
    fi
  done < "$path"
}

# ----------------------------------------------------------------------------
# Shuffle-bag selector — draws every matching entry once before repeating
# ----------------------------------------------------------------------------
queue_file_for() {
  local theme="$1" intensity="$2"
  printf '%s/%s__%s.queue' "$STATE_DIR" "$theme" "$intensity"
}

refill_queue() {
  local theme="$1" intensity="$2"
  local qf; qf=$(queue_file_for "$theme" "$intensity")
  local files=() f

  while IFS= read -r f; do
    if [[ "$intensity" == "any" ]]; then
      files+=("$f")
    elif grep -q "^INTENSITY=${intensity}$" "$f" 2>/dev/null; then
      files+=("$f")
    fi
  done < <(find "$VARIANTS_DIR/$theme" -maxdepth 1 -name '*.variant' 2>/dev/null | sort)

  if [[ ${#files[@]} -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${files[@]}" | shuf > "$qf"
  return 0
}

next_variant_path() {
  local theme="$1" intensity="$2"
  local qf; qf=$(queue_file_for "$theme" "$intensity")
  ensure_dirs
  if [[ ! -s "$qf" ]]; then
    refill_queue "$theme" "$intensity" || return 1
  fi
  local path
  path=$(head -n1 "$qf")
  tail -n +2 "$qf" > "${qf}.tmp" 2>/dev/null && mv "${qf}.tmp" "$qf"
  [[ -n "$path" ]] || return 1
  echo "$path"
}

# ----------------------------------------------------------------------------
# Rendering
# ----------------------------------------------------------------------------
type_out() {
  local text="$1" speed="$2"
  if [[ "$speed" == "typewriter" ]]; then
    local i c
    for (( i=0; i<${#text}; i++ )); do
      c="${text:$i:1}"
      printf '%s' "$c"
      [[ "$c" != $'\n' ]] && sleep 0.012
    done
  else
    printf '%s' "$text"
  fi
}

render_variant() {
  local path="$1" speed="$2"
  parse_variant_file "$path"
  line
  printf "${BOLD_MAGENTA}%s${RESET}  ${GRAY}[id:%s | %s]${RESET}\n" "$V_TITLE" "$V_ID" "$V_INTENSITY"
  line
  type_out "$V_DESC" "$speed"
  echo
  printf "${BOLD_CYAN}"
  printf '%s' "$V_ASCII"
  printf "${RESET}"
  line
}

# ----------------------------------------------------------------------------
# Game loop
# ----------------------------------------------------------------------------
run_game() {
  load_prompt
  local theme="${PROMPT[THEME]}" intensity="${PROMPT[INTENSITY]}" rounds="${PROMPT[ROUNDS]}" speed="${PROMPT[SPEED]}"

  if [[ ! -d "$VARIANTS_DIR/$theme" ]]; then
    banner
    warn "Theme '$theme' from your prompt has no folder under $VARIANTS_DIR."
    local picked
    if picked=$(pick_theme_interactive); then
      theme="$picked"
    else
      press_enter
      return 1
    fi
  fi

  banner
  printf "${BOLD}%s${RESET}\n" "${PROMPT[TITLE]}"
  printf "${GRAY}%s${RESET}\n" "${PROMPT[DESC]}"
  printf "${GRAY}theme=%s  intensity=%s  rounds=%s  speed=%s${RESET}\n" "$theme" "$intensity" "$rounds" "$speed"

  local played=0
  while true; do
    if [[ "$rounds" != "0" ]] && (( played >= rounds )); then
      break
    fi
    local path
    if ! path=$(next_variant_path "$theme" "$intensity"); then
      error "No entries found for theme '$theme' at intensity '$intensity'. Add .variant files under $VARIANTS_DIR/$theme/."
      break
    fi
    render_variant "$path" "$speed"
    ensure_dirs
    printf '%s theme=%s id=%s intensity=%s\n' "$(date -Iseconds 2>/dev/null || date)" "$theme" "$V_ID" "$V_INTENSITY" >> "$HISTORY_LOG"
    played=$((played+1))

    printf "\n${YELLOW}[Enter] next   [r] reshuffle now   [q] quit: ${RESET}"
    read -r a
    case "$a" in
      q|Q) break ;;
      r|R) refill_queue "$theme" "$intensity" ;;
    esac
  done

  echo
  success "Session ended — $played round(s) played."
  press_enter
}

# ----------------------------------------------------------------------------
# Content library management
# ----------------------------------------------------------------------------
manage_library() {
  banner
  step "Content Library"
  local themes=()
  while IFS= read -r t; do themes+=("$t"); done < <(list_themes)

  if [[ ${#themes[@]} -eq 0 ]]; then
    warn "No themes yet. Create a folder under $VARIANTS_DIR/<theme>/ and add .variant files."
    press_enter
    return 0
  fi

  printf "${GRAY}Library root: %s${RESET}\n\n" "$VARIANTS_DIR"
  for t in "${themes[@]}"; do
    local total low medium high
    total=$(find "$VARIANTS_DIR/$t" -maxdepth 1 -name '*.variant' | wc -l | tr -d ' ')
    low=$(grep -lE '^INTENSITY=low$' "$VARIANTS_DIR/$t"/*.variant 2>/dev/null | wc -l | tr -d ' ')
    medium=$(grep -lE '^INTENSITY=medium$' "$VARIANTS_DIR/$t"/*.variant 2>/dev/null | wc -l | tr -d ' ')
    high=$(grep -lE '^INTENSITY=high$' "$VARIANTS_DIR/$t"/*.variant 2>/dev/null | wc -l | tr -d ' ')
    printf "${BOLD_CYAN}%s${RESET}  ${GRAY}— %s total (low:%s medium:%s high:%s)${RESET}\n" "$t" "$total" "$low" "$medium" "$high"
  done
  press_enter
}

# ----------------------------------------------------------------------------
# History
# ----------------------------------------------------------------------------
view_history() {
  banner
  step "Session History"
  ensure_dirs
  if [[ -s "$HISTORY_LOG" ]]; then
    tail -n 25 "$HISTORY_LOG"
  else
    warn "No history yet — play a session first."
  fi
  press_enter
}

# ----------------------------------------------------------------------------
# Main menu
# ----------------------------------------------------------------------------
main_menu() {
  while true; do
    banner
    load_prompt
    printf "${GRAY}Active prompt: %s  (theme=%s, intensity=%s)${RESET}\n\n" "${PROMPT[TITLE]}" "${PROMPT[THEME]}" "${PROMPT[INTENSITY]}"

    printf "  ${BOLD_GREEN}1)${RESET} Quick Start      ${GRAY}— run using the current prompt as-is${RESET}\n"
    printf "  ${BOLD_GREEN}2)${RESET} Custom Prompt Mode ${GRAY}— view/edit config, then start${RESET}\n"
    printf "  ${BOLD_YELLOW}3)${RESET} Manage Content Library\n"
    printf "  ${CYAN}4)${RESET} Session History\n"
    printf "  ${BOLD_RED}0)${RESET} Exit\n\n"
    line
    printf "${YELLOW}Select an option [0-4]: ${RESET}"
    read -r choice

    case "$choice" in
      1) run_game ;;
      2) custom_prompt_menu ;;
      3) manage_library ;;
      4) view_history ;;
      0)
        banner
        printf "${BOLD_MAGENTA}Session closed.${RESET}\n\n"
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
seed_demo_theme_if_empty
[[ -f "$PROMPT_FILE" ]] || { default_prompt_values; write_prompt_file; }
main_menu
