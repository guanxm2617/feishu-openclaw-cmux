#!/usr/bin/env bash
# cmux-notify-feishu.sh — Send a task-completion or status notification to Feishu.
# Checks subscription state before sending. Does NOT interfere with cmux native notifications.
#
# Usage:
#   cmux-notify-feishu.sh [options] "message"
#
# Options:
#   -s, --status <status>    completed | waiting | error | started
#   -p, --project <name>     Project name (default: current dir basename)
#   -b, --branch <name>      Git branch (auto-detected)
#   -w, --workspace <name>   CMUX workspace name
#   -i, --terminal-id <id>   CMUX terminal ID (e.g. 3-1)
#   -t, --target <open_id>   Override Feishu target (skips state lookup)
#   --force                  Send even if not subscribed
#   -h, --help               Show help
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/state.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
STATUS=""
PROJECT="$(basename "$(pwd)")"
BRANCH="$(git branch --show-current 2>/dev/null || echo '')"
WORKSPACE=""
TERMINAL_ID=""
TARGET_OVERRIDE=""
FORCE=false
MESSAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--status)      STATUS="$2"; shift 2 ;;
    -p|--project)     PROJECT="$2"; shift 2 ;;
    -b|--branch)      BRANCH="$2"; shift 2 ;;
    -w|--workspace)   WORKSPACE="$2"; shift 2 ;;
    -i|--terminal-id) TERMINAL_ID="$2"; shift 2 ;;
    -t|--target)      TARGET_OVERRIDE="$2"; shift 2 ;;
    --force)          FORCE=true; shift ;;
    -h|--help)        grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'; exit 0 ;;
    -*)               echo "Unknown option: $1" >&2; exit 1 ;;
    *)                MESSAGE="$1"; shift ;;
  esac
done

[[ -z "$MESSAGE" ]] && { echo "ERROR: message required" >&2; exit 1; }

# ── Check subscription (unless forced) ────────────────────────────────────────
if ! $FORCE && ! state_is_subscribed; then
  # Not subscribed — exit silently, cmux native notifications handle it
  exit 0
fi

# ── Resolve target ────────────────────────────────────────────────────────────
TARGET="${TARGET_OVERRIDE:-$(state_get_target)}"
[[ -z "$TARGET" ]] && { echo "ERROR: No Feishu target. Ask user to send '连接CMUX' in Feishu first." >&2; exit 1; }

# ── Status config ─────────────────────────────────────────────────────────────
case "${STATUS:-}" in
  completed|done|finish*) COLOR="green";  EMOJI="✅"; LABEL="已完成" ;;
  waiting|input*)         COLOR="yellow"; EMOJI="⏳"; LABEL="等待指令" ;;
  error|fail*)            COLOR="red";    EMOJI="❌"; LABEL="发生错误" ;;
  started|begin*)         COLOR="blue";   EMOJI="🚀"; LABEL="已启动" ;;
  *)                      COLOR="blue";   EMOJI="🤖"; LABEL="通知" ;;
esac

# ── Build rich markdown message ───────────────────────────────────────────────
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

DETAILS=""
[[ -n "$WORKSPACE" ]]    && DETAILS+="- **工作区:** ${WORKSPACE}\n"
[[ -n "$TERMINAL_ID" ]]  && DETAILS+="- **终端 ID:** ${TERMINAL_ID}\n"
[[ -n "$PROJECT" ]]      && DETAILS+="- **项目:** ${PROJECT}\n"
[[ -n "$BRANCH" ]]       && DETAILS+="- **分支:** ${BRANCH}\n"
DETAILS+="- **时间:** ${TIMESTAMP}"

TEXT="${EMOJI} **CMUX — ${LABEL}**\n\n${MESSAGE}\n\n---\n${DETAILS}"

# ── Send ──────────────────────────────────────────────────────────────────────
send_text() {
  openclaw message send \
    --channel feishu \
    --target "chat:${TARGET}" \
    --message "$TEXT" \
    2>&1
}

if ! send_text; then
  sleep 2
  send_text
fi
