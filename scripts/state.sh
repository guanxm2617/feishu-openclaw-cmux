#!/usr/bin/env bash
# state.sh — Read/write cmux skill state (target session + subscription).
# Source this file in other scripts: source "$(dirname "$0")/state.sh"
#
set -euo pipefail

STATE_FILE="$HOME/.openclaw/skills/cmux/state.json"

# ── Ensure state file exists ──────────────────────────────────────────────────
_state_init() {
  if [[ ! -f "$STATE_FILE" ]]; then
    printf '{"target":"","subscribed":false,"last_seen":""}\n' > "$STATE_FILE"
  fi
}

# ── Read a key from state.json ────────────────────────────────────────────────
# Usage: state_get <key>
# Returns the value or empty string
state_get() {
  local key="$1"
  _state_init
  python3 -c "
import json, sys
with open('$STATE_FILE') as f:
    d = json.load(f)
val = d.get('$key', '')
if isinstance(val, bool):
    print('true' if val else 'false')
else:
    print(val)
" 2>/dev/null || echo ""
}

# ── Write a key to state.json ─────────────────────────────────────────────────
# Usage: state_set <key> <value>
# value can be: a string, "true", or "false"
state_set() {
  local key="$1"
  local value="$2"
  _state_init
  STATE_FILE="$STATE_FILE" STATE_KEY="$key" STATE_VALUE="$value" python3 - <<'PYEOF'
import json, os, tempfile, fcntl
state_file = os.environ['STATE_FILE']
key = os.environ['STATE_KEY']
value = os.environ['STATE_VALUE']

# Acquire exclusive lock
lock_fd = os.open(state_file, os.O_RDONLY | os.O_CREAT)
fcntl.flock(lock_fd, fcntl.LOCK_EX)
try:
    with open(state_file) as f:
        d = json.load(f)
except Exception:
    d = {}

if value == 'true':
    d[key] = True
elif value == 'false':
    d[key] = False
else:
    d[key] = value

fd, tmp_path = tempfile.mkstemp(prefix='.state.', suffix='.json', dir=os.path.dirname(state_file) or '.')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write('\n')
    os.replace(tmp_path, state_file)
except Exception:
    try:
        os.unlink(tmp_path)
    except FileNotFoundError:
        pass
    raise
finally:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    os.close(lock_fd)
PYEOF
}

# ── Record sender from environment or argument ────────────────────────────────
# Call this at the top of any script that receives a Feishu message.
# Usage: state_record_sender [explicit_target]
# Priority: explicit arg > CMUX_FEISHU_TARGET env > OPENCLAW_SENDER_ID env
state_record_sender() {
  local explicit="${1:-}"
  local sender=""

  if [[ -n "$explicit" ]]; then
    sender="$explicit"
  elif [[ -n "${CMUX_FEISHU_TARGET:-}" ]]; then
    sender="$CMUX_FEISHU_TARGET"
  elif [[ -n "${OPENCLAW_SENDER_ID:-}" ]]; then
    sender="$OPENCLAW_SENDER_ID"
  fi

  if [[ -n "$sender" ]]; then
    state_set "target" "$sender"
    state_set "last_seen" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  fi
}

# ── Get the current notification target ───────────────────────────────────────
# Returns the stored target, or falls back to CMUX_FEISHU_TARGET env
state_get_target() {
  local stored
  stored=$(state_get "target")
  if [[ -n "$stored" ]]; then
    echo "$stored"
  elif [[ -n "${CMUX_FEISHU_TARGET:-}" ]]; then
    echo "$CMUX_FEISHU_TARGET"
  else
    echo ""
  fi
}

# ── Check if notifications are subscribed ────────────────────────────────────
# Returns exit code 0 if subscribed, 1 if not
state_is_subscribed() {
  local val
  val=$(state_get "subscribed")
  [[ "$val" == "true" ]]
}

# ── Notification seen-ID management ──────────────────────────────────────────
# seen_notification_ids is stored as a JSON array in state.json.
# Uses quoted heredoc + env vars to avoid shell injection in Python code.

# Check if a notification ID has already been processed.
# Returns "true" or "false" (stdout).
state_has_seen_notification() {
  local id="$1"
  _state_init
  STATE_FILE="$STATE_FILE" NOTIF_ID="$id" python3 - <<'PYEOF'
import json, os
state_file = os.environ['STATE_FILE']
notif_id = os.environ['NOTIF_ID']
try:
    with open(state_file) as f:
        d = json.load(f)
    ids = d.get('seen_notification_ids', [])
    print('true' if isinstance(ids, list) and notif_id in ids else 'false')
except Exception:
    print('false')
PYEOF
}

# Add a notification ID to the seen list. Trims to MAX_SEEN oldest entries.
state_add_seen_notification() {
  local id="$1"
  local max_ids="${CMUX_DAEMON_MAX_SEEN:-200}"
  _state_init
  STATE_FILE="$STATE_FILE" NOTIF_ID="$id" MAX_IDS="$max_ids" python3 - <<'PYEOF'
import json, os, tempfile, fcntl
state_file = os.environ['STATE_FILE']
notif_id = os.environ['NOTIF_ID']
max_ids = int(os.environ.get('MAX_IDS', '200'))

# Acquire exclusive lock
lock_fd = os.open(state_file, os.O_RDONLY | os.O_CREAT)
fcntl.flock(lock_fd, fcntl.LOCK_EX)
try:
    with open(state_file) as f:
        d = json.load(f)
except Exception:
    d = {}

ids = d.get('seen_notification_ids', [])
if not isinstance(ids, list):
    ids = []
if notif_id not in ids:
    ids.append(notif_id)
if len(ids) > max_ids:
    ids = ids[-max_ids:]
d['seen_notification_ids'] = ids

fd, tmp_path = tempfile.mkstemp(prefix='.state.', suffix='.json', dir=os.path.dirname(state_file) or '.')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write('\n')
    os.replace(tmp_path, state_file)
except Exception:
    try:
        os.unlink(tmp_path)
    except FileNotFoundError:
        pass
    raise
finally:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    os.close(lock_fd)
PYEOF
}

# Get/set daemon PID.
state_get_daemon_pid() { state_get daemon_pid 2>/dev/null || echo ""; }
state_set_daemon_pid() { state_set daemon_pid "$1"; }
