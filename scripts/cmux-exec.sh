#!/usr/bin/env bash
# cmux-exec.sh — Send a command to a specific cmux terminal by stable or legacy ID.
#
# Usage:
#   cmux-exec.sh <terminal-id> <command text>
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SEND="$DIR/cmux-send.sh"
source "$DIR/state.sh"
source "$DIR/terminal-id.sh"

# Configuration for auto-read
WAIT_TIME="${CMUX_EXEC_WAIT:-3}"
[[ "$WAIT_TIME" -gt 10 ]] && WAIT_TIME=10
READ_LINES="${CMUX_EXEC_READ_LINES:-20}"
[[ "$READ_LINES" -gt 50 ]] && READ_LINES=50

# Classify execution status based on output
classify_status() {
  local output="$1"
  local line_count=$(echo "$output" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')

  if echo "$output" | grep -qiE 'error|fail|failed|traceback|exception|command not found|permission denied|fatal:|ERROR:|Error:'; then
    echo "⚠️ 疑似失败"
  elif echo "$output" | grep -qiE 'success|completed|done|finished|✓|✅'; then
    echo "✅ 看起来成功"
  elif [[ "$line_count" -gt 3 ]]; then
    echo "✅ 看起来已执行"
  else
    echo "📝 无明显输出"
  fi
}

# Auto-record sender if called from openclaw context
state_record_sender

if [[ $# -lt 2 ]]; then
  echo "Usage: cmux-exec.sh <terminal-id> <command>" >&2
  echo "Run cmux-list-all.sh to see available terminal IDs." >&2
  exit 1
fi

TERMINAL_REF="$1"
shift
COMMAND="$*"

TERMINAL_RECORDS=$(cmux_collect_terminal_records 2>/dev/null) || {
  echo "ERROR: Cannot enumerate cmux terminals. Is cmux running?" >&2
  exit 1
}

RESOLVED_RECORD=""
if RESOLVED_RECORD="$(cmux_resolve_terminal_ref "$TERMINAL_RECORDS" "$TERMINAL_REF")"; then
  :
else
  RESOLVE_STATUS=$?
  if [[ "$RESOLVE_STATUS" -eq 2 ]]; then
    echo "ERROR: Terminal ID '$TERMINAL_REF' is ambiguous. Run cmux-list-all.sh and use a longer ID." >&2
  else
    echo "ERROR: Terminal ID '$TERMINAL_REF' not found. Run cmux-list-all.sh to see available terminal IDs." >&2
  fi
  exit 1
fi

IFS='|' read -r WS_IDX _ WORKSPACE_NAME PANE_IDX PANE_UUID <<< "$RESOLVED_RECORD"
TERMINAL_ID="$(cmux_terminal_short_id_from_uuid "$TERMINAL_RECORDS" "$PANE_UUID")"
LEGACY_TERMINAL_ID="${WS_IDX}-${PANE_IDX}"

ORIGINAL_WS_IDX=$(bash "$SEND" list_workspaces 2>/dev/null | awk '/^\*/{print $2}' | tr -d ':') || ORIGINAL_WS_IDX=""

bash "$SEND" select_workspace "$WS_IDX" >/dev/null 2>&1 || {
  echo "ERROR: Workspace $WS_IDX not found" >&2
  exit 1
}
sleep 0.1

bash "$SEND" focus_surface "$PANE_IDX" >/dev/null 2>&1 || {
  echo "ERROR: Pane $PANE_IDX not found in workspace $WS_IDX" >&2
  exit 1
}

bash "$SEND" send_surface "$PANE_IDX" "${COMMAND}"
sleep 0.05
bash "$SEND" send_key_surface "$PANE_IDX" enter

# Wait for execution
sleep "$WAIT_TIME"

# Read terminal output
OUTPUT_RAW=$(bash "$SEND" read_screen "$PANE_IDX" --lines "$READ_LINES" 2>/dev/null || echo "")

# Classify status
STATUS=$(classify_status "$OUTPUT_RAW")

# Restore original workspace
if [[ -n "$ORIGINAL_WS_IDX" && "$ORIGINAL_WS_IDX" != "$WS_IDX" ]]; then
  bash "$SEND" select_workspace "$ORIGINAL_WS_IDX" >/dev/null 2>&1 || true
fi

# Generate enhanced output
OUTPUT="✅ **CMUX 指令已发送**\n\n"
OUTPUT+="- **工作区:** ${WORKSPACE_NAME:-$WS_IDX}\n"
OUTPUT+="- **终端 ID:** ${TERMINAL_ID}\n"
OUTPUT+="- **位置:** ${LEGACY_TERMINAL_ID}\n"
OUTPUT+="- **指令内容:** \`${COMMAND}\`\n"
OUTPUT+="- **时间:** $(date '+%Y-%m-%d %H:%M:%S')\n\n"
OUTPUT+="---\n\n"
OUTPUT+="📊 **执行结果**\n\n"
OUTPUT+="**状态:** ${STATUS}\n\n"

if [[ -n "$OUTPUT_RAW" ]]; then
  OUTPUT+="**最近输出:**\n\`\`\`\n${OUTPUT_RAW}\n\`\`\`\n\n"
else
  OUTPUT+="**最近输出:** (无输出)\n\n"
fi

OUTPUT+="💡 如需查看完整输出，可使用：\`cmux读取 ${TERMINAL_ID}\`"

echo -e "$OUTPUT"
