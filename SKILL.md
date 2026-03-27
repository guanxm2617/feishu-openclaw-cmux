---
name: cmux
description: Control cmux terminal panes (send keystrokes, manage workspaces, read output) and send agent notifications to Feishu. Use for AI coding agent workflows running inside cmux on macOS.
metadata:
  { "openclaw": { "emoji": "🖥️", "os": ["darwin"], "requires": { "bins": ["nc", "openclaw"] } } }
---

# cmux Terminal Control

cmux is a Ghostty-based macOS terminal for AI coding agents. It exposes a Unix Domain Socket at:

```
$HOME/Library/Application Support/cmux/cmux.sock
```

All control commands are sent as newline-terminated text over this socket.

## Helper Script

Always use the bundled helper for socket communication:

```bash
~/.openclaw/skills/cmux/scripts/cmux-send.sh <command> [args]
```

The script auto-discovers the socket path (env override → well-known path → /tmp → lsof scan) and retries once on failure.

---

## Direction 1: Feishu → cmux (Remote terminal control)

### Important: workspaces vs surfaces

- **Workspace** = a tab in the sidebar (e.g. "codex", "北新", "sw")
- **Surface** = a terminal pane inside a workspace (one workspace can have multiple panes)
- `list_surfaces` only shows panes **in the currently active workspace**
- To target a pane in a different workspace, first `select_workspace`, then `list_surfaces`

### Full workflow to target a specific pane

```bash
# 1. List all workspaces
~/.openclaw/skills/cmux/scripts/cmux-send.sh list_workspaces
# Output: * 0: <uuid> cmux  /  1: <uuid> sw  /  2: <uuid> 北新  /  3: <uuid> codex

# 2. Switch to target workspace (e.g. codex = index 3)
~/.openclaw/skills/cmux/scripts/cmux-send.sh select_workspace 3

# 3. List panes in that workspace
~/.openclaw/skills/cmux/scripts/cmux-send.sh list_surfaces
# Output: * 0: <uuid>  /  1: <uuid>  (multiple panes)

# 4. Send keys to a specific pane (e.g. pane 1)
~/.openclaw/skills/cmux/scripts/cmux-send.sh send_keys 1 "continue working\n"
```

### List workspaces

```bash
~/.openclaw/skills/cmux/scripts/cmux-send.sh list_workspaces
```

### Get current workspace

```bash
~/.openclaw/skills/cmux/scripts/cmux-send.sh current_workspace
```

### Send text to a pane

```bash
# Send text to specific pane by index
~/.openclaw/skills/cmux/scripts/cmux-send.sh send_surface 0 "continue working on the auth module"

# Send special key (enter, tab, escape, ctrl-c, ctrl-d)
~/.openclaw/skills/cmux/scripts/cmux-send.sh send_key_surface 0 enter
~/.openclaw/skills/cmux/scripts/cmux-send.sh send_key_surface 0 ctrl-c
```

> **Always use cmux-exec.sh for combined text+enter** — it handles workspace switching automatically.

### Read terminal output

```bash
# Last 20 lines of pane 0
~/.openclaw/skills/cmux/scripts/cmux-send.sh read_screen 0 --lines 20
```

### Focus a pane

```bash
~/.openclaw/skills/cmux/scripts/cmux-send.sh focus_surface 0
~/.openclaw/skills/cmux/scripts/cmux-send.sh focus_pane 0
```

### Focus a workspace by index

```bash
~/.openclaw/skills/cmux/scripts/cmux-send.sh select_workspace 0
```

### Create a new workspace

```bash
~/.openclaw/skills/cmux/scripts/cmux-send.sh new_workspace
```

### Split a pane

```bash
# Split horizontally
~/.openclaw/skills/cmux/scripts/cmux-send.sh split horizontal

# Split vertically
~/.openclaw/skills/cmux/scripts/cmux-send.sh split vertical
```

### Read terminal output (base64)

```bash
~/.openclaw/skills/cmux/scripts/cmux-send.sh read_surface_text_base64 0 | base64 -d
```

---

## Direction 2: cmux → Feishu (Agent notifications)

### Send a notification to Feishu

```bash
CMUX_FEISHU_TARGET="<chat_id_or_open_id>" \
  ~/.openclaw/skills/cmux/scripts/cmux-notify-feishu.sh \
    --status completed \
    "Task finished: refactored auth module"
```

### Options

| Flag | Description |
|------|-------------|
| `-t / --target` | Feishu chat_id or user open_id (or set `CMUX_FEISHU_TARGET`) |
| `-p / --project` | Project name (defaults to current directory name) |
| `-b / --branch` | Git branch (auto-detected) |
| `-s / --status` | `completed` \| `waiting` \| `error` \| `started` |

### Status emojis

| Status | Emoji |
|--------|-------|
| completed / done | ✅ |
| waiting / input | ⏳ |
| error / fail | ❌ |
| started / begin | 🚀 |
| (default) | 🤖 |

---

## Wire into Claude Code hooks

Add to `~/.claude/settings.json` to auto-notify Feishu when Claude Code stops:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CMUX_FEISHU_TARGET='oc_xxxx' bash ~/.openclaw/skills/cmux/scripts/cmux-notify-feishu.sh --status waiting 'Agent is waiting for your input'"
          }
        ]
      }
    ]
  }
}
```

---

## Feishu → cmux: Recognized command patterns

When a user messages the bot in Feishu, recognize these patterns and act immediately:

### Pattern 1: Connect current Feishu chat to CMUX

**Trigger phrases (any of):** `连接CMUX`, `connect cmux`, `绑定CMUX`, `绑定当前会话`, `连接当前会话`

**Action:**
```bash
bash ~/.openclaw/skills/cmux/scripts/cmux-subscribe.sh connect --target <conversation_label>
```

`<conversation_label>` should be the current Feishu chat id, typically `oc_xxx`. This records the chat target used by later CMUX notifications.

Returns plain text confirmation. Send to Feishu.

### Pattern 2: List workspaces

**Trigger phrases (any of):** `列出cmux工作区`, `cmux工作区`, `cmux列出终端`, `列出cmux终端`, `cmux终端列表`, `列出终端`, `list cmux`, `cmux列表`, `查看cmux`, `show cmux workspaces`, `cmux状态`, `cmux workspace list`

**Action:**
```bash
CMUX_FEISHU_TARGET="<conversation_label>" \
  bash ~/.openclaw/skills/cmux/scripts/cmux-list-all.sh
```

The script outputs rich markdown. Send it directly to Feishu using:
```bash
openclaw message send --channel feishu --target "chat:<chat_id>" --message "<output>"
```

Always pass the current Feishu `conversation_label` as `CMUX_FEISHU_TARGET` so the script can persist the correct chat target for future notifications.

### Pattern 3: Send command to terminal

**Trigger phrase:** `cmux发送 <终端ID> <指令>`

**Examples the user might send:**
- `cmux发送 3-1 继续工作`
- `cmux发送 2-0 git status`
- `cmux发送 0-0 y`
- `CMUX发送 3-1 完成auth模块`
- `cmux终端 2-1 执行 ls -la`

**Action:**
```bash
CMUX_FEISHU_TARGET="<conversation_label>" \
  bash ~/.openclaw/skills/cmux/scripts/cmux-exec.sh <终端ID> <指令>
```

The script outputs rich markdown confirmation **including execution result and recent terminal output** (waits ~3s for command to run). Send it to Feishu:
```bash
openclaw message send --channel feishu --target "chat:<chat_id>" --message "<output>"
```

Configuration (optional env vars):
- `CMUX_EXEC_WAIT` — seconds to wait before reading (default: 3, max: 10)
- `CMUX_EXEC_READ_LINES` — lines to read after execution (default: 20, max: 50)

### Pattern 4: Read terminal output

**Trigger phrases:** `cmux读取 <终端ID>`, `cmux查看 <终端ID>`, `读取终端 <终端ID>`

**Examples the user might send:**
- `cmux读取 3-1`
- `cmux查看 2-0`
- `cmux读取 3-1 最近100行`
- `cmux读取 3-1 全部`
- `cmux读取 0-0 50`

**Action:**
```bash
CMUX_FEISHU_TARGET="<conversation_label>" \
  bash ~/.openclaw/skills/cmux/scripts/cmux-read.sh <终端ID> [lines]
```

Argument formats for `[lines]`:
- `最近N行` — read N lines (e.g. `最近100行`)
- `全部` — read maximum lines (default max: 200)
- A plain number (e.g. `50`)
- Omit for default (50 lines)

Configuration (optional env vars):
- `CMUX_READ_DEFAULT_LINES` — default lines to read (default: 50)
- `CMUX_READ_MAX_LINES` — maximum lines allowed (default: 200)

The script outputs rich markdown with terminal content. Send it to Feishu:
```bash
openclaw message send --channel feishu --target "chat:<chat_id>" --message "<output>"
```

### Pattern 5: Subscribe to CMUX notifications

**Trigger phrases:** `订阅CMUX`, `subscribe cmux`, `开启CMUX通知`, `cmux通知开启`

**Action:**
```bash
bash ~/.openclaw/skills/cmux/scripts/cmux-subscribe.sh subscribe --target <conversation_label>
```

This starts a background polling daemon that checks native CMUX notifications every ~4 seconds and forwards new ones to the recorded Feishu session.

Returns plain text confirmation. Send to Feishu.

### Pattern 6: Unsubscribe from CMUX notifications

**Trigger phrases:** `取消订阅`, `unsubscribe cmux`, `关闭CMUX通知`, `cmux通知关闭`

**Action:**
```bash
bash ~/.openclaw/skills/cmux/scripts/cmux-subscribe.sh unsubscribe --target <conversation_label>
```

This stops the background polling daemon. Native CMUX notifications inside the app are unaffected.

Returns plain text confirmation. Send to Feishu.

### Pattern 7: Check subscription status

**Trigger phrases:** `CMUX订阅状态`, `cmux status`, `订阅状态`

**Action:**
```bash
bash ~/.openclaw/skills/cmux/scripts/cmux-subscribe.sh status
```

Returns plain text status. Send to Feishu.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `cmux socket not found` | Make sure cmux app is running |
| `Failed to communicate` | Check socket permissions: `ls -la "$HOME/Library/Application Support/cmux/"` |
| `nc: command not found` | Install netcat: `brew install netcat` |
| Socket auth error | Open cmux Settings → Socket Control → set to "Automation mode" or "Full open access" |
| Feishu send fails | Run `openclaw status` to check feishu channel health |
