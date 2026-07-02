#!/usr/bin/env bash
# ~/.claude/statusline.sh — Claude Code status line (Windows-compatible fork)
#
# Two-line output:
#   Line 1: brand  model (gradient)  │  context bar + %  │  5h bar + 7d bar
#   Line 2: branch (± ahead/behind, dirty*)  │  +added/-removed  │  dir  │  agent/worktree
#
# Env vars:
#   CLAUDE_STATUSLINE_ASCII=1     force plain ASCII (no Unicode/emoji/truecolor)
#   CLAUDE_STATUSLINE_NERDFONT=1  use Nerd Font icons instead of emoji
#   CLAUDE_STATUSLINE_EMOJI=0     disable emoji, keep plain Unicode symbols
#   CLAUDE_STATUSLINE_POWERLINE=1 Powerline-style separators (default: follows NERDFONT)
#   CLAUDE_STATUSLINE_JQ=/path    explicit path to a jq binary (auto-detected otherwise)
#   COLORTERM=truecolor|24bit     set by most terminals; also auto-enabled under Windows Terminal (WT_SESSION)

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Environment detection
# ═══════════════════════════════════════════════════════════════

USE_ASCII="${CLAUDE_STATUSLINE_ASCII:-0}"
USE_NERDFONT="${CLAUDE_STATUSLINE_NERDFONT:-0}"
USE_POWERLINE="${CLAUDE_STATUSLINE_POWERLINE:-$USE_NERDFONT}"
USE_TRUECOLOR=0
if [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" || -n "${WT_SESSION:-}" ]]; then
  USE_TRUECOLOR=1
fi

USE_EMOJI="${CLAUDE_STATUSLINE_EMOJI:-1}"
if [[ "$USE_ASCII" == "1" ]]; then USE_EMOJI=0; fi

# ═══════════════════════════════════════════════════════════════
# Colors & symbols
# ═══════════════════════════════════════════════════════════════

RST='\033[0m'
CYAN='\033[36m'
BLUE='\033[34m'
GRAY='\033[90m'
DIM='\033[2m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
MAGENTA='\033[35m'

# Anthropic brand purple (#7266EA)
if (( USE_TRUECOLOR )); then
  PURPLE='\033[38;2;114;102;234m'
else
  PURPLE='\033[35m'
fi

if [[ "$USE_ASCII" == "1" ]]; then
  S_BRAND="<>"
  S_BRANCH=">"
  S_WARN="!"
  S_PROMPT=">"
  S_TIME=""
  S_COST=""
  SEP=" | "
elif [[ "$USE_NERDFONT" == "1" ]]; then
  S_BRAND="◆"
  S_BRANCH=" "
  S_WARN=" 󰀦"
  S_PROMPT="❯"
  S_TIME="󰔟 "
  S_COST=" "
  if [[ "$USE_POWERLINE" == "1" ]]; then
    SEP="  "
  else
    SEP=" │ "
  fi
elif (( USE_EMOJI )); then
  S_BRAND="✨"
  S_BRANCH="🌿 "
  S_WARN=" 🔥"
  S_PROMPT="❯"
  S_TIME="⏱️ "
  S_COST=""
  S_DIR="📁 "
  S_RATE="🚦 "
  S_ADD="+"
  S_RM="-"
  S_AGENT_ICON="🤖"
  S_WORKTREE_ICON="🌳"
  SEP="${GRAY} · ${RST}"
else
  S_BRAND="◆"
  S_BRANCH="⎇"
  S_WARN=" ⚠"
  S_PROMPT="❯"
  S_TIME=""
  S_COST=""
  S_DIR=""
  S_RATE=""
  S_ADD="+"
  S_RM="-"
  S_AGENT_ICON="⚙"
  S_WORKTREE_ICON="⚙"
  if [[ "$USE_POWERLINE" == "1" ]]; then
    SEP="  "
  else
    SEP=" │ "
  fi
fi

: "${S_DIR:=}"
: "${S_RATE:=}"
: "${S_ADD:=+}"
: "${S_RM:=-}"
: "${S_AGENT_ICON:=⚙}"
: "${S_WORKTREE_ICON:=⚙}"

# ═══════════════════════════════════════════════════════════════
# Gradient text (per-character truecolor interpolation)
# ═══════════════════════════════════════════════════════════════

gradient_text() {
  local text="$1" r1="$2" g1="$3" b1="$4" r2="$5" g2="$6" b2="$7" fallback="${8:-$CYAN}"
  local len=${#text}
  if (( len == 0 )); then
    return
  fi
  if (( ! USE_TRUECOLOR )) || [[ "$USE_ASCII" == "1" ]]; then
    printf '%s' "${fallback}${text}${RST}"
    return
  fi
  local out="" i t r g b ch
  for (( i=0; i<len; i++ )); do
    if (( len > 1 )); then
      t=$(( i * 1000 / (len - 1) ))
    else
      t=0
    fi
    r=$(( r1 + (r2 - r1) * t / 1000 ))
    g=$(( g1 + (g2 - g1) * t / 1000 ))
    b=$(( b1 + (b2 - b1) * t / 1000 ))
    ch="${text:i:1}"
    out+="\\033[38;2;${r};${g};${b}m${ch}"
  done
  out+="${RST}"
  printf '%s' "$out"
}

# Percentage → green(low)-to-red(high) continuous gradient RGB, "r g b".
# Used as the gradient endpoint color for rate-limit text.
pct_gradient_rgb() {
  local p="$1" r g b t
  if (( p < 0 )); then p=0; fi
  if (( p > 100 )); then p=100; fi
  if (( p <= 50 )); then
    t=$(( p * 1000 / 50 ))
    r=$(( 46 + (241 - 46) * t / 1000 ))
    g=$(( 204 + (196 - 204) * t / 1000 ))
    b=$(( 113 + (15 - 113) * t / 1000 ))
  else
    t=$(( (p - 50) * 1000 / 50 ))
    r=$(( 241 + (231 - 241) * t / 1000 ))
    g=$(( 196 + (76 - 196) * t / 1000 ))
    b=$(( 15 + (60 - 15) * t / 1000 ))
  fi
  printf '%d %d %d' "$r" "$g" "$b"
}

# Generic gradient progress bar (green→yellow→orange→red).
# Requires global GRAD_R/GRAD_G/GRAD_B to be set before calling.
make_bar() {
  local pct="$1" width="${2:-10}"
  if (( pct < 0 )); then pct=0; fi
  if (( pct > 100 )); then pct=100; fi
  local filled=$(( pct * width / 100 ))
  if (( filled > width )); then filled=$width; fi
  local out="" i idx
  if [[ "$USE_ASCII" == "1" ]]; then
    for (( i=0; i<width; i++ )); do
      if (( i < filled )); then out+="#"; else out+="-"; fi
    done
  elif (( USE_TRUECOLOR )); then
    for (( i=0; i<width; i++ )); do
      idx=$(( i * 10 / width ))
      if (( idx > 9 )); then idx=9; fi
      if (( i < filled )); then
        out+="\\033[38;2;${GRAD_R[$idx]};${GRAD_G[$idx]};${GRAD_B[$idx]}m█"
      else
        out+="\\033[38;2;60;60;60m░"
      fi
    done
    out+="${RST}"
  else
    local bar_color
    if (( pct >= 90 )); then bar_color="$RED"
    elif (( pct >= 70 )); then bar_color="$YELLOW"
    else bar_color="$GREEN"; fi
    for (( i=0; i<width; i++ )); do
      if (( i < filled )); then out+="█"; else out+="░"; fi
    done
    out="${bar_color}${out}${RST}"
  fi
  printf '%s' "$out"
}

# Formats a Unix epoch as local clock time: "14:32" if today, "Thu 14:32"
# otherwise (the 7d reset is usually a different day).
format_reset_clock() {
  local epoch="$1" today tgt_day
  today=$(date +%Y%m%d)
  tgt_day=$(date -d "@${epoch}" +%Y%m%d 2>/dev/null)
  if [[ "$tgt_day" == "$today" ]]; then
    date -d "@${epoch}" +%H:%M 2>/dev/null
  else
    date -d "@${epoch}" '+%a %H:%M' 2>/dev/null
  fi
}

# ═══════════════════════════════════════════════════════════════
# Fallback output
# ═══════════════════════════════════════════════════════════════

fallback_prompt() {
  printf '%b' "${GRAY}${1:-─}${RST}"
  exit 0
}

JQ_BIN="${CLAUDE_STATUSLINE_JQ:-jq}"
if ! command -v "$JQ_BIN" &>/dev/null; then
  for cand in "$HOME/bin/jq.exe" "$HOME/bin/jq" "/c/ProgramData/chocolatey/bin/jq.exe"; do
    if [[ -x "$cand" ]]; then JQ_BIN="$cand"; break; fi
  done
fi
command -v "$JQ_BIN" &>/dev/null || fallback_prompt "─ │ jq not found"

# ═══════════════════════════════════════════════════════════════
# Read JSON (single jq call)
# ═══════════════════════════════════════════════════════════════

input=$(cat)

parsed=$(echo "$input" | "$JQ_BIN" -r '
  (.model.display_name // ""),
  (.context_window.used_percentage // 0 | tostring),
  (.cost.total_cost_usd // 0 | tostring),
  (.workspace.current_dir // "." | gsub("\\\\"; "/") | split("/") | last),
  (.worktree.branch // ""),
  (.rate_limits.five_hour.used_percentage // -1 | tostring),
  (.rate_limits.seven_day.used_percentage // -1 | tostring),
  (.agent.name // ""),
  (.workspace.current_dir // "."),
  (.cost.total_lines_added // 0 | tostring),
  (.cost.total_lines_removed // 0 | tostring),
  (.cost.total_duration_ms // 0 | tostring),
  (.context_window.context_window_size // 0 | tostring),
  (.worktree.name // ""),
  (.rate_limits.five_hour.resets_at // 0 | tostring),
  (.rate_limits.seven_day.resets_at // 0 | tostring),
  "END"
' 2>/dev/null) || fallback_prompt "─ │ parse error"

# Native Windows jq.exe writes CRLF (text-mode stdio); strip stray CR before parsing fields.
parsed="${parsed//$'\r'/}"

{
  IFS= read -r model_name
  IFS= read -r ctx_pct
  IFS= read -r cost
  IFS= read -r dir
  IFS= read -r branch
  IFS= read -r rate5h
  IFS= read -r rate7d
  IFS= read -r agent_name
  IFS= read -r cwd_full
  IFS= read -r lines_add
  IFS= read -r lines_rm
  IFS= read -r duration_ms
  IFS= read -r ctx_size
  IFS= read -r wt_name
  IFS= read -r reset5h_at
  IFS= read -r reset7d_at
  IFS= read -r _sentinel
} <<< "$parsed"

# Display fields may contain backslashes (Windows paths). Double them so the
# final printf '%b' can't misparse them as escape starts (\U, \0nn, ...),
# which would eat characters and corrupt the rest of the line.
# cwd_full is left alone — it's used as a real filesystem path for git/-d.
model_name="${model_name//\\/\\\\}"
dir="${dir//\\/\\\\}"
branch="${branch//\\/\\\\}"
agent_name="${agent_name//\\/\\\\}"
wt_name="${wt_name//\\/\\\\}"

# ═══════════════════════════════════════════════════════════════
# Model
# ═══════════════════════════════════════════════════════════════

model="${model_name:-─}"
model="${model#Claude }"

# ═══════════════════════════════════════════════════════════════
# Context progress bar
# ═══════════════════════════════════════════════════════════════

pct_int=${ctx_pct%.*}
pct_int=${pct_int:-0}
if (( pct_int < 0 )); then pct_int=0; fi
if (( pct_int > 100 )); then pct_int=100; fi

# Gradient stops (truecolor): green → yellow → orange → red
GRAD_R=(46 116 186 241 239 236 233 231 211 192)
GRAD_G=(204 195 186 196 161 126 101 76 66 57)
GRAD_B=(113 89 64 15 24 34 44 60 50 43)

bar="$(make_bar "$pct_int" 10)"

# Percentage text color (matches overall bar color)
if (( pct_int >= 90 )); then pct_color="$RED"
elif (( pct_int >= 70 )); then pct_color="$YELLOW"
else pct_color="$GREEN"; fi

# Warning glyph
ctx_warn=""
if (( pct_int >= 90 )); then ctx_warn="${RED}${S_WARN}${RST}"; fi

# Context window size (only shown if not already implied by the model name)
ctx_size_int=${ctx_size:-0}
ctx_label=""
if [[ "$model" != *context* && "$model" != *Context* ]]; then
  if (( ctx_size_int >= 1000000 )); then ctx_label=" ${GRAY}1M${RST}"
  elif (( ctx_size_int >= 200000 )); then ctx_label=" ${GRAY}200k${RST}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Cost (parsed but not displayed by default — see README)
# ═══════════════════════════════════════════════════════════════

cost_val="${cost:-0}"
cost_fmt=$(printf '%.2f' "$cost_val" 2>/dev/null || echo "0.00")
cost_int=${cost_val%.*}
cost_int=${cost_int:-0}

if (( cost_int >= 10 )); then cost_color="$RED"
elif (( cost_int >= 5 )); then cost_color="$YELLOW"
elif [[ "$cost_fmt" == "0.00" ]]; then cost_color="$GRAY"
else cost_color="$YELLOW"; fi

# ═══════════════════════════════════════════════════════════════
# Git branch, dirty flag, ahead/behind (cached)
# ═══════════════════════════════════════════════════════════════

GIT_CACHE="/tmp/claude-statusline-git-cache"
GIT_CACHE_MAX_AGE=5

git_branch="${branch:-}"
dirty=""

git_cache_is_stale() {
  [[ ! -f "$GIT_CACHE" ]] && return 0
  local cache_mtime
  cache_mtime=$(stat -c %Y "$GIT_CACHE" 2>/dev/null || stat -f %m "$GIT_CACHE" 2>/dev/null || echo 0)
  local cache_age=$(( $(date +%s) - cache_mtime ))
  (( cache_age > GIT_CACHE_MAX_AGE ))
}

if [[ -n "${cwd_full:-}" && -d "${cwd_full:-}" ]]; then
  if git_cache_is_stale; then
    if git -C "$cwd_full" rev-parse --git-dir &>/dev/null; then
      cached_branch="${git_branch}"
      if [[ -z "$cached_branch" ]]; then
        cached_branch=$(git -C "$cwd_full" -c core.useBuiltinFSMonitor=false branch --show-current 2>/dev/null) || true
        if [[ -z "$cached_branch" ]]; then
          cached_branch=$(git -C "$cwd_full" rev-parse --short HEAD 2>/dev/null) || true
        fi
      fi
      cached_dirty=""
      if ! git -C "$cwd_full" -c core.useBuiltinFSMonitor=false diff --quiet 2>/dev/null || \
         ! git -C "$cwd_full" -c core.useBuiltinFSMonitor=false diff --cached --quiet 2>/dev/null; then
        cached_dirty="*"
      fi
      cached_ahead=0
      cached_behind=0
      if git -C "$cwd_full" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' &>/dev/null; then
        read -r cached_behind cached_ahead < <(git -C "$cwd_full" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
        cached_ahead="${cached_ahead:-0}"
        cached_behind="${cached_behind:-0}"
      fi
      echo "${cached_branch}|${cached_dirty}|${cached_ahead}|${cached_behind}" > "$GIT_CACHE"
    else
      echo "|||" > "$GIT_CACHE"
    fi
  fi

  ahead=0
  behind=0
  if [[ -f "$GIT_CACHE" ]]; then
    IFS='|' read -r cached_br cached_dt cached_ah cached_bh < "$GIT_CACHE"
    if [[ -z "$git_branch" ]]; then git_branch="${cached_br}"; fi
    dirty="${cached_dt}"
    ahead="${cached_ah:-0}"
    behind="${cached_bh:-0}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Lines added/removed (hidden when zero)
# ═══════════════════════════════════════════════════════════════

lines_add=${lines_add:-0}
lines_rm=${lines_rm:-0}
lines_section=""
if (( lines_add > 0 || lines_rm > 0 )); then
  lines_section="${GREEN}${S_ADD}${lines_add}${RST}/${RED}${S_RM}${lines_rm}${RST}"
fi

# ═══════════════════════════════════════════════════════════════
# Rate limits (5h / 7d) — gradient text + gradient bar. Always shown, even
# before Claude Code has usage data (e.g. right at session start), as a
# "--%"  placeholder — keeps the layout stable instead of the section
# popping in after the first turn.
# ═══════════════════════════════════════════════════════════════

rate_section=""
rate5h_int=${rate5h%.*}; rate5h_int=${rate5h_int:-0}
rate7d_int=${rate7d%.*}; rate7d_int=${rate7d_int:-0}

reset5h_at=${reset5h_at:-0}
reset7d_at=${reset7d_at:-0}

rate_parts=""
if (( rate5h_int >= 0 )); then
  read -r er eg eb <<< "$(pct_gradient_rgb "$rate5h_int")"
  rate_parts+="$(gradient_text "5h:${rate5h_int}%" 46 204 113 "$er" "$eg" "$eb" "$GREEN") $(make_bar "$rate5h_int" 10)"
  if (( reset5h_at > 0 )); then
    rate_parts+=" ${GRAY}↻ $(format_reset_clock "$reset5h_at")${RST}"
  fi
else
  rate_parts+="${GRAY}5h:--%${RST} $(make_bar 0 10)"
fi
rate_parts+="${SEP}"
if (( rate7d_int >= 0 )); then
  read -r er eg eb <<< "$(pct_gradient_rgb "$rate7d_int")"
  rate_parts+="$(gradient_text "7d:${rate7d_int}%" 46 204 113 "$er" "$eg" "$eb" "$GREEN") $(make_bar "$rate7d_int" 10)"
  if (( reset7d_at > 0 )); then
    rate_parts+=" ${GRAY}↻ $(format_reset_clock "$reset7d_at")${RST}"
  fi
else
  rate_parts+="${GRAY}7d:--%${RST} $(make_bar 0 10)"
fi
if [[ -n "$rate_parts" ]]; then
  rate_section="${SEP}${S_RATE}${rate_parts}"
fi

# ═══════════════════════════════════════════════════════════════
# Assemble line 1
# ═══════════════════════════════════════════════════════════════

model_grad="$(gradient_text "$model" 114 102 234 45 212 191)"
line1="${PURPLE}${S_BRAND}${RST} ${model_grad}"
line1+="${SEP}${bar} ${pct_color}${pct_int}%${RST}${ctx_warn}${ctx_label}"
line1+="${rate_section}"

# ═══════════════════════════════════════════════════════════════
# Assemble line 2
# ═══════════════════════════════════════════════════════════════

parts=()
if [[ -n "$git_branch" ]]; then
  dirty_mark=""
  if [[ -n "$dirty" ]]; then dirty_mark="${YELLOW}${dirty}${RST}"; fi
  ahead_behind=""
  if (( ${ahead:-0} > 0 )); then ahead_behind+=" ${GREEN}↑${ahead}${RST}"; fi
  if (( ${behind:-0} > 0 )); then ahead_behind+=" ${YELLOW}↓${behind}${RST}"; fi
  parts+=("${GRAY}${S_BRANCH}${git_branch}${RST}${dirty_mark}${ahead_behind}")
fi
if [[ -n "$lines_section" ]]; then
  parts+=("${lines_section}")
fi
dir_grad="$(gradient_text "$dir" 59 130 246 168 85 247 "$BLUE")"
parts+=("${S_DIR}${dir_grad}")

# Agent / worktree indicator (only shown when active)
if [[ -n "${wt_name:-}" ]]; then
  parts+=("${YELLOW}${S_WORKTREE_ICON} worktree:${wt_name}${RST}")
elif [[ -n "${agent_name:-}" ]]; then
  parts+=("${YELLOW}${S_AGENT_ICON} ${agent_name}${RST}")
fi

line2=""
for i in "${!parts[@]}"; do
  if (( i > 0 )); then
    line2+="${SEP}"
  fi
  line2+="${parts[$i]}"
done

# ═══════════════════════════════════════════════════════════════
# Output (two lines — Claude Code renders its own input prompt below)
# ═══════════════════════════════════════════════════════════════

printf '%b\n%b' "$line1" "$line2"
