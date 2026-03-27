#!/usr/bin/env bash
# cmux-subscribe.sh — Handle subscription commands from Feishu.
#
# Usage:
#   cmux-subscribe.sh connect  [--target <open_id>]   # 连接CMUX
#   cmux-subscribe.sh subscribe [--target <open_id>]  # 订阅CMUX
#   cmux-subscribe.sh unsubscribe [--target <open_id>]# 取消订阅
#   cmux-subscribe.sh status                          # 查看订阅状态
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/state.sh"

ACTION="${1:-}"
shift || true

TARGET_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_ARG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Record sender if provided
if [[ -n "$TARGET_ARG" ]]; then
  state_record_sender "$TARGET_ARG"
elif [[ -n "${OPENCLAW_SENDER_ID:-}" ]]; then
  state_record_sender "$OPENCLAW_SENDER_ID"
elif [[ -n "${CMUX_FEISHU_TARGET:-}" ]]; then
  state_record_sender "$CMUX_FEISHU_TARGET"
fi

TARGET=$(state_get_target)

case "$ACTION" in
  connect)
    if [[ -z "$TARGET" ]]; then
      echo "ERROR: No Feishu target to record." >&2
      exit 1
    fi
    echo "✅ CMUX 已连接"
    echo "会话已记录: ${TARGET}"
    echo "当前订阅状态: $(state_get subscribed)"
    ;;

  subscribe)
    # Check if daemon already running
    EXISTING_PID=$(state_get_daemon_pid)
    if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
      echo "✅ 已订阅 CMUX 通知（守护进程运行中，PID: ${EXISTING_PID}）"
      echo "发送 '取消订阅' 可关闭通知。"
      exit 0
    fi
    # Start daemon in background
    bash "$DIR/cmux-daemon.sh" &
    DAEMON_PID=$!
    # Record PID before confirming to minimize untracked-process window
    state_set_daemon_pid "$DAEMON_PID"
    state_set subscribed true
    echo "✅ 已订阅 CMUX 通知"
    echo "守护进程已启动 (PID: $DAEMON_PID)"
    echo "后续 Claude Code / Codex 完成任务或需要授权时，将自动推送到本会话。"
    echo "发送 '取消订阅' 可关闭通知。"
    ;;

  unsubscribe)
    EXISTING_PID=$(state_get_daemon_pid)
    if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
      kill "$EXISTING_PID" 2>/dev/null || true
    fi
    state_set_daemon_pid ""
    state_set subscribed false
    echo "🔕 已取消订阅 CMUX 通知"
    echo "CMUX 原生通知（通知环/侧边栏）不受影响。"
    echo "发送 '订阅CMUX' 可重新开启。"
    ;;

  status)
    echo "📊 CMUX 订阅状态"
    echo "目标会话: $(state_get target)"
    echo "订阅状态: $(state_get subscribed)"
    echo "最后更新: $(state_get last_seen)"
    ;;

  *)
    echo "Usage: cmux-subscribe.sh connect|subscribe|unsubscribe|status" >&2
    exit 1
    ;;
esac
