#!/usr/bin/env bash
# cmux-daemon.sh — Poll CMUX notifications and forward new ones to Feishu.
# Started by cmux-subscribe.sh; stopped via kill on unsubscribe.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SEND="$DIR/cmux-send.sh"
NOTIFY="$DIR/cmux-notify-feishu.sh"
source "$DIR/state.sh"

POLL_INTERVAL="${CMUX_DAEMON_POLL:-4}"

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

    # Forward to Feishu; mark seen only on success
    if bash "$NOTIFY" ${STATUS:+--status "$STATUS"} "$MSG" 2>/dev/null; then
      state_add_seen_notification "$id" || true
    fi

  done <<< "$RAW"
done
