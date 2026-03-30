#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/scripts/terminal-id.sh"

if [[ ! -f "$LIB" ]]; then
  echo "missing terminal-id library: $LIB" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CURRENT_WS_FILE="$TMP_DIR/current_workspace"
printf '0\n' > "$CURRENT_WS_FILE"
export CURRENT_WS_FILE

MOCK_SEND="$TMP_DIR/mock-cmux-send.sh"
cat > "$MOCK_SEND" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CURRENT_WS_FILE="${CURRENT_WS_FILE:?}"
cmd="${1:-}"
shift || true

case "$cmd" in
  list_workspaces)
    cat <<'OUT'
* 0: ws-aaaa Alpha
  1: ws-bbbb Beta
OUT
    ;;
  current_workspace)
    cat "$CURRENT_WS_FILE"
    ;;
  select_workspace)
    printf '%s\n' "$1" > "$CURRENT_WS_FILE"
    ;;
  list_surfaces)
    ws="$(cat "$CURRENT_WS_FILE")"
    case "$ws" in
      0)
        cat <<'OUT'
* 0: a1b2c3d4e5f61111 shell
  1: deadbeef99992222 logs
OUT
        ;;
      1)
        cat <<'OUT'
* 0: 1122334455667788 api
OUT
        ;;
      *)
        ;;
    esac
    ;;
  *)
    echo "unsupported mock command: $cmd" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_SEND"

sleep() { :; }

source "$LIB"
SEND="$MOCK_SEND"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "assertion failed: $message" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

records="$(cmux_collect_terminal_records)"
record_count="$(printf '%s\n' "$records" | awk 'NF{count++} END{print count+0}')"
assert_eq "3" "$record_count" "collects all live terminals"

short_id="$(cmux_terminal_short_id_from_uuid "$records" "a1b2c3d4e5f61111")"
assert_eq "a1b2c3d4" "$short_id" "uses short UUID as primary id"

resolved_uuid="$(cmux_resolve_terminal_ref "$records" "a1b2c3d4")"
assert_eq "0|ws-aaaa|Alpha|0|a1b2c3d4e5f61111" "$resolved_uuid" "resolves short UUID refs"

resolved_legacy="$(cmux_resolve_terminal_ref "$records" "1-0")"
assert_eq "1|ws-bbbb|Beta|0|1122334455667788" "$resolved_legacy" "keeps legacy workspace-pane refs working"

rendered="$(cmux_render_terminal_label "$records" "0" "1" "deadbeef99992222")"
assert_eq "deadbeef (位置 0-1)" "$rendered" "renders stable id with legacy position hint"

echo "ok"
