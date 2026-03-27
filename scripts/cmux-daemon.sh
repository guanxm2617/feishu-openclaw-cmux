#!/usr/bin/env bash
# cmux-daemon.sh — Poll CMUX notifications and forward new ones to Feishu.
# Started by cmux-subscribe.sh; stopped via kill on unsubscribe.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SEND="$DIR/cmux-send.sh"
NOTIFY="$DIR/cmux-notify-feishu.sh"
source "$DIR/state.sh"

POLL_INTERVAL="${CMUX_DAEMON_POLL:-4}"

resolve_terminal_context() {
  local target_tab_id="$1"
  local target_surface_id="$2"
  local workspaces original_idx=""
  local result_workspace="" result_terminal=""

  [[ -z "$target_surface_id" ]] && return 0

  workspaces=$(bash "$SEND" list_workspaces 2>/dev/null) || return 0
  original_idx=$(printf '%s\n' "$workspaces" | awk '/^\*/{print $2}' | tr -d ':')

  while IFS= read -r ws_line; do
    local line idx rest ws_uuid ws_name surfaces

    [[ -z "$ws_line" ]] && continue
    line="${ws_line#\* }"
    line="${line#  }"
    idx="${line%%:*}"
    rest="${line#*: }"
    ws_uuid="${rest%% *}"
    ws_name="${rest#* }"

    if [[ -n "$target_tab_id" && "$ws_uuid" != "$target_tab_id" ]]; then
      continue
    fi

    bash "$SEND" select_workspace "$idx" >/dev/null 2>&1 || continue
    sleep 0.1
    surfaces=$(bash "$SEND" list_surfaces 2>/dev/null) || surfaces=""

    while IFS= read -r surface_line; do
      local pane_line pane_idx pane_uuid

      [[ -z "$surface_line" ]] && continue
      pane_line="${surface_line#\* }"
      pane_line="${pane_line#  }"
      pane_idx="${pane_line%%:*}"
      pane_uuid="${pane_line#*: }"
      pane_uuid="${pane_uuid%% *}"

      if [[ "$pane_uuid" == "$target_surface_id" ]]; then
        result_workspace="$ws_name"
        result_terminal="${idx}-${pane_idx}"
        break 2
      fi
    done <<< "$surfaces"
  done <<< "$workspaces"

  if [[ -n "$original_idx" ]]; then
    bash "$SEND" select_workspace "$original_idx" >/dev/null 2>&1 || true
  fi

  printf '%s|%s\n' "$result_workspace" "$result_terminal"
}

# On exit reset subscription state so Feishu knows daemon stopped
trap 'state_set subscribed false; state_set daemon_pid ""' EXIT

while true; do
  sleep "$POLL_INTERVAL"

  # Fetch notifications from CMUX socket; skip on error
  RAW=$(bash "$SEND" list_notifications 2>/dev/null || true)
  [[ -z "$RAW" || "$RAW" == "No notifications" ]] && continue

  # Process each notification line
  # Format: index:id|tabId|surfaceId|read/unread|title|subtitle|body
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Extract id: take field before first |, then strip leading "digits:"
    id=$(echo "$line" | cut -d'|' -f1 | sed 's/^[0-9]*://')
    tab_id=$(echo "$line" | cut -d'|' -f2)
    surface_id=$(echo "$line" | cut -d'|' -f3)
    title=$(echo "$line" | cut -d'|' -f5)
    subtitle=$(echo "$line" | cut -d'|' -f6)
    body=$(echo "$line" | cut -d'|' -f7)

    [[ -z "$id" ]] && continue

    # Skip already-seen notifications
    seen=$(state_has_seen_notification "$id")
    [[ "$seen" == "true" ]] && continue

    # Classify status from title keywords
    STATUS=""
    if echo "$title" | grep -qiE 'error|fail|failed'; then
      STATUS="error"
    elif echo "$title" | grep -qiE 'waiting|input|authoriz|permission'; then
      STATUS="waiting"
    elif echo "$title" | grep -qiE 'complet|done|finish|success'; then
      STATUS="completed"
    elif echo "$title" | grep -qiE 'start|begin|running'; then
      STATUS="started"
    fi

    # Build message with actual newlines
    MSG="${title}"
    [[ -n "$subtitle" ]] && MSG+=$'\n'"${subtitle}"
    [[ -n "$body" ]] && MSG+=$'\n'"${body}"

    workspace_name=""
    terminal_id=""
    if [[ -n "$surface_id" ]]; then
      context=$(resolve_terminal_context "$tab_id" "$surface_id")
      workspace_name="${context%%|*}"
      terminal_id="${context#*|}"
    fi

    # Forward to Feishu; mark seen only on success
    notify_args=()
    [[ -n "$STATUS" ]] && notify_args+=(--status "$STATUS")
    [[ -n "$workspace_name" ]] && notify_args+=(--workspace "$workspace_name")
    [[ -n "$terminal_id" ]] && notify_args+=(--terminal-id "$terminal_id")

    if bash "$NOTIFY" "${notify_args[@]}" "$MSG" 2>/dev/null; then
      state_add_seen_notification "$id" || true
    fi

  done <<< "$RAW"
done
