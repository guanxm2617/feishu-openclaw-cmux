#!/usr/bin/env bash
# terminal-id.sh — Shared helpers for stable cmux terminal IDs.
# Record format: WS_IDX|WS_UUID|WS_NAME|PANE_IDX|PANE_UUID

cmux_collect_terminal_records() {
  local workspaces original_idx=""
  local ws_line line idx rest ws_uuid ws_name surfaces
  local surface_line pane_line pane_idx pane_uuid

  workspaces=$(bash "$SEND" list_workspaces 2>/dev/null) || return 1
  original_idx=$(printf '%s\n' "$workspaces" | awk '/^\*/{print $2}' | tr -d ':')

  while IFS= read -r ws_line; do
    [[ -z "$ws_line" ]] && continue
    line="${ws_line#\* }"
    line="${line#  }"
    idx="${line%%:*}"
    rest="${line#*: }"
    ws_uuid="${rest%% *}"
    ws_name="${rest#* }"

    bash "$SEND" select_workspace "$idx" >/dev/null 2>&1 || continue
    sleep 0.1
    surfaces=$(bash "$SEND" list_surfaces 2>/dev/null) || surfaces=""

    while IFS= read -r surface_line; do
      [[ -z "$surface_line" ]] && continue
      pane_line="${surface_line#\* }"
      pane_line="${pane_line#  }"
      pane_idx="${pane_line%%:*}"
      pane_uuid="${pane_line#*: }"
      pane_uuid="${pane_uuid%% *}"
      printf '%s|%s|%s|%s|%s\n' "$idx" "$ws_uuid" "$ws_name" "$pane_idx" "$pane_uuid"
    done <<< "$surfaces"
  done <<< "$workspaces"

  if [[ -n "$original_idx" ]]; then
    bash "$SEND" select_workspace "$original_idx" >/dev/null 2>&1 || true
  fi
}

cmux_terminal_short_id_from_uuid() {
  local records="$1"
  local pane_uuid="$2"
  local min_len=8
  local max_len="${#pane_uuid}"
  local length prefix count

  [[ -z "$pane_uuid" ]] && return 1

  if [[ "$max_len" -lt "$min_len" ]]; then
    printf '%s\n' "$pane_uuid"
    return 0
  fi

  for ((length=min_len; length<=max_len; length++)); do
    prefix="${pane_uuid:0:length}"
    count=$(printf '%s\n' "$records" | awk -F'|' -v prefix="$prefix" '
      BEGIN { want = tolower(prefix); count = 0 }
      NF >= 5 {
        uuid = tolower($5)
        if (index(uuid, want) == 1) {
          count++
        }
      }
      END { print count + 0 }
    ')
    if [[ "$count" -eq 1 ]]; then
      printf '%s\n' "$prefix"
      return 0
    fi
  done

  printf '%s\n' "$pane_uuid"
}

cmux_resolve_terminal_ref() {
  local records="$1"
  local ref="$2"
  local matches

  if [[ "$ref" =~ ^[0-9]+-[0-9]+$ ]]; then
    matches=$(printf '%s\n' "$records" | awk -F'|' -v ws="${ref%-*}" -v pane="${ref#*-}" '
      $1 == ws && $4 == pane { print }
    ')
  else
    matches=$(printf '%s\n' "$records" | awk -F'|' -v raw_ref="$ref" '
      BEGIN { want = tolower(raw_ref) }
      NF >= 5 {
        uuid = tolower($5)
        if (index(uuid, want) == 1) {
          print
        }
      }
    ')
  fi

  local count
  count=$(printf '%s\n' "$matches" | awk 'NF{count++} END{print count + 0}')
  if [[ "$count" -eq 1 ]]; then
    printf '%s\n' "$matches"
    return 0
  fi
  if [[ "$count" -gt 1 ]]; then
    return 2
  fi
  return 1
}

cmux_render_terminal_label() {
  local records="$1"
  local ws_idx="$2"
  local pane_idx="$3"
  local pane_uuid="$4"
  local short_id

  short_id="$(cmux_terminal_short_id_from_uuid "$records" "$pane_uuid")" || return 1
  printf '%s (位置 %s-%s)\n' "$short_id" "$ws_idx" "$pane_idx"
}
