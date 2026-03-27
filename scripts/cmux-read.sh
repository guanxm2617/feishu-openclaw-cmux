#!/usr/bin/env bash
# cmux-read.sh — Read terminal output from a specific cmux terminal by ID.
#
# Usage:
#   cmux-read.sh <WS_IDX-PANE_IDX> [lines]
#   cmux-read.sh <WS_IDX-PANE_IDX> 最近N行
#   cmux-read.sh <WS_IDX-PANE_IDX> 全部
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SEND="$DIR/cmux-send.sh"
source "$DIR/state.sh"

# Auto-record sender if called from openclaw context
state_record_sender

# Configuration
DEFAULT_LINES="${CMUX_READ_DEFAULT_LINES:-50}"
MAX_LINES="${CMUX_READ_MAX_LINES:-200}"

if [[ $# -lt 1 ]]; then
  echo "Usage: cmux-read.sh <WS_IDX-PANE_IDX> [lines|最近N行|全部]" >&2
  echo "Run cmux-list-all.sh to see available terminal IDs." >&2
  exit 1
fi

TERMINAL_ID="$1"
LINES="$DEFAULT_LINES"

if [[ $# -ge 2 ]]; then
  ARG="$2"
  if [[ "$ARG" =~ ^最近([0-9]+)行$ ]]; then
    LINES="${BASH_REMATCH[1]}"
  elif [[ "$ARG" == "全部" ]]; then
    LINES="$MAX_LINES"
  elif [[ "$ARG" =~ ^[0-9]+$ ]]; then
    LINES="$ARG"
  else
    echo "ERROR: Invalid lines argument '$ARG'. Use a number, '最近N行', or '全部'" >&2
    exit 1
  fi
fi

# Clamp to max
[[ "$LINES" -gt "$MAX_LINES" ]] && LINES="$MAX_LINES"

if [[ ! "$TERMINAL_ID" =~ ^[0-9]+-[0-9]+$ ]]; then
  echo "ERROR: Invalid terminal ID '$TERMINAL_ID'. Expected format: WS_IDX-PANE_IDX (e.g. 3-1)" >&2
  exit 1
fi

WS_IDX="${TERMINAL_ID%-*}"
PANE_IDX="${TERMINAL_ID#*-}"

# Read workspace name
WORKSPACE_NAME=$(bash "$SEND" list_workspaces 2>/dev/null | awk -v idx="$WS_IDX" '
  {
    line=$0
    sub(/^\* /, "", line)
    sub(/^  /, "", line)
    split(line, a, ": ")
    if (a[1] == idx) {
      sub(/^[^ ]+ /, "", a[2])
      print a[2]
      exit
    }
  }
') || WORKSPACE_NAME=""

# Switch to target workspace to read
bash "$SEND" select_workspace "$WS_IDX" >/dev/null 2>&1 || {
  echo "ERROR: Workspace $WS_IDX not found" >&2
  exit 1
}
sleep 0.1

bash "$SEND" focus_surface "$PANE_IDX" >/dev/null 2>&1 || {
  echo "ERROR: Pane $PANE_IDX not found in workspace $WS_IDX" >&2
  exit 1
}

# Read terminal output
OUTPUT_RAW=$(bash "$SEND" read_screen "$PANE_IDX" --lines "$LINES" 2>/dev/null || echo "")

# Format output for Feishu
OUTPUT="📖 **CMUX 终端输出**\n\n"
OUTPUT+="- **工作区:** ${WORKSPACE_NAME:-$WS_IDX}\n"
OUTPUT+="- **终端 ID:** ${TERMINAL_ID}\n"
OUTPUT+="- **读取行数:** ${LINES}\n"
OUTPUT+="- **时间:** $(date '+%Y-%m-%d %H:%M:%S')\n\n"
OUTPUT+="---\n\n"

if [[ -n "$OUTPUT_RAW" ]]; then
  OUTPUT+="**终端内容:**\n\`\`\`\n${OUTPUT_RAW}\n\`\`\`\n"
else
  OUTPUT+="**终端内容:** (无输出)\n"
fi

echo -e "$OUTPUT"
