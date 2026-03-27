#!/usr/bin/env bash
# cmux-send.sh — Send a command to the cmux Unix socket and print the response.
#
# Usage:
#   cmux-send.sh <command> [args...]
#
# Examples:
#   cmux-send.sh list_workspaces
#   cmux-send.sh list_surfaces
#   cmux-send.sh send_keys 0 "hello"
#   cmux-send.sh focus_surface 0
#   cmux-send.sh current_workspace
#
set -euo pipefail

# ── Socket discovery ──────────────────────────────────────────────────────────
find_socket() {
  # 1. Explicit env override
  if [[ -n "${CMUX_SOCKET_PATH:-}" && -S "${CMUX_SOCKET_PATH}" ]]; then
    echo "$CMUX_SOCKET_PATH"
    return 0
  fi

  # 2. Well-known production path
  local default="$HOME/Library/Application Support/cmux/cmux.sock"
  if [[ -S "$default" ]]; then
    echo "$default"
    return 0
  fi

  # 3. /tmp fallback (debug builds)
  local tmp_sock
  tmp_sock=$(find /tmp -maxdepth 1 -name 'cmux*.sock' 2>/dev/null | head -1)
  if [[ -n "$tmp_sock" && -S "$tmp_sock" ]]; then
    echo "$tmp_sock"
    return 0
  fi

  # 4. lsof scan (last resort, slightly slower)
  local lsof_sock
  lsof_sock=$(lsof -U 2>/dev/null | awk '/cmux.*\.sock/{print $NF}' | head -1)
  if [[ -n "$lsof_sock" && -S "$lsof_sock" ]]; then
    echo "$lsof_sock"
    return 0
  fi

  echo "ERROR: cmux socket not found. Is cmux running?" >&2
  return 1
}

# ── Main ──────────────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  echo "Usage: cmux-send.sh <command> [args...]" >&2
  echo "Run 'cmux-send.sh list_workspaces' to verify connection." >&2
  exit 1
fi

SOCKET=$(find_socket)

# Build the payload: first arg is command, rest become space-joined args
CMD="$1"
shift
if [[ $# -gt 0 ]]; then
  PAYLOAD="$CMD $*"
else
  PAYLOAD="$CMD"
fi

# Send via Python (handles spaces in path, available on all macOS)
send_once() {
  python3 - "$SOCKET" "$PAYLOAD" <<'PYEOF'
import socket, sys, time
sock_path = sys.argv[1]
payload   = sys.argv[2] + "\n"
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(sock_path)
    s.sendall(payload.encode())
    chunks = []
    s.settimeout(2)
    while True:
        try:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        except socket.timeout:
            break
    s.close()
    sys.stdout.buffer.write(b"".join(chunks))
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

RESPONSE=$(send_once) || RESPONSE=$(send_once) || {
  echo "ERROR: Failed to communicate with cmux socket at $SOCKET" >&2
  exit 1
}

echo "$RESPONSE"
