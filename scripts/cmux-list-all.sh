#!/usr/bin/env bash
# cmux-list-all.sh — List all cmux workspaces and their terminal panes.
# Outputs rich markdown suitable for Feishu post messages.
# Auto-records sender session when called from openclaw.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SEND="$DIR/cmux-send.sh"
source "$DIR/state.sh"
source "$DIR/terminal-id.sh"

# Auto-record sender if called from openclaw context
state_record_sender

# ── Get all workspaces ────────────────────────────────────────────────────────
WORKSPACES=$(bash "$SEND" list_workspaces 2>/dev/null) || {
  echo "ERROR: Cannot connect to cmux socket. Is cmux running?" >&2
  exit 1
}
TERMINAL_RECORDS=$(cmux_collect_terminal_records 2>/dev/null) || TERMINAL_RECORDS=""

# Parse workspace lines
ORIGINAL_IDX=""
declare -a WS_INDEXES WS_UUIDS WS_NAMES

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  focused=false
  if [[ "$line" == \** ]]; then
    focused=true
    line="${line#\* }"
  else
    line="${line#  }"
  fi
  idx="${line%%:*}"
  rest="${line#*: }"
  uuid="${rest%% *}"
  name="${rest#* }"
  WS_INDEXES+=("$idx")
  WS_UUIDS+=("$uuid")
  WS_NAMES+=("$name")
  if $focused; then
    ORIGINAL_IDX="$idx"
  fi
done <<< "$WORKSPACES"

# ── Enumerate panes per workspace ─────────────────────────────────────────────
TOTAL_WORKSPACES=${#WS_INDEXES[@]}
TOTAL_TERMINALS=0
OUTPUT="📋 **CMUX 工作区列表**\n\n"

for i in "${!WS_INDEXES[@]}"; do
  idx="${WS_INDEXES[$i]}"
  name="${WS_NAMES[$i]}"

  bash "$SEND" select_workspace "$idx" >/dev/null 2>&1
  sleep 0.1

  SURFACES=$(bash "$SEND" list_surfaces 2>/dev/null) || SURFACES=""

  OUTPUT+="**工作区 ${idx}: ${name}**\n"

  if [[ -z "$SURFACES" ]]; then
    OUTPUT+="  (无终端)\n\n"
    continue
  fi

  while IFS= read -r sline; do
    [[ -z "$sline" ]] && continue
    focused_pane=false
    if [[ "$sline" == \** ]]; then
      focused_pane=true
      sline="${sline#\* }"
    else
      sline="${sline#  }"
    fi
    pane_idx="${sline%%:*}"
    pane_uuid="${sline#*: }"
    pane_uuid="${pane_uuid%% *}"
    terminal_label="$(cmux_render_terminal_label "$TERMINAL_RECORDS" "$idx" "$pane_idx" "$pane_uuid")"
    TOTAL_TERMINALS=$((TOTAL_TERMINALS + 1))

    if $focused_pane; then
      OUTPUT+="  ▶ 终端 **${terminal_label}** ← 当前活跃\n"
    else
      OUTPUT+="    终端 **${terminal_label}**\n"
    fi
  done <<< "$SURFACES"
  OUTPUT+="\n"
done

# ── Restore original workspace ────────────────────────────────────────────────
if [[ -n "$ORIGINAL_IDX" ]]; then
  bash "$SEND" select_workspace "$ORIGINAL_IDX" >/dev/null 2>&1 || true
fi

# ── Footer ────────────────────────────────────────────────────────────────────
OUTPUT+="---\n"
OUTPUT+="📊 共 **${TOTAL_WORKSPACES}** 个工作区 / **${TOTAL_TERMINALS}** 个终端\n\n"
OUTPUT+="💡 **发送指令:** \`cmux发送 终端ID 你的指令\`\n"
OUTPUT+="例如: \`cmux发送 a1b2c3d4 继续工作\`"

# ── Output ────────────────────────────────────────────────────────────────────
echo -e "$OUTPUT"
