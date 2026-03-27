# Claude Code Hook Configuration for CMUX → Feishu Notifications

Add this to your `~/.claude/settings.json` to enable automatic Feishu notifications when Claude Code stops (waiting for input):

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.openclaw/skills/cmux/scripts/cmux-notify-feishu.sh --status waiting --workspace \"$(basename $(pwd))\" \"Agent 等待指令\""
          }
        ]
      }
    ]
  }
}
```

## What This Does

When Claude Code stops and waits for your input:
1. The Stop hook triggers
2. `cmux-notify-feishu.sh` checks if you're subscribed (`state.json`)
3. If subscribed, sends a rich markdown notification to Feishu via `openclaw message send`
4. The notification includes:
   - Status emoji (⏳ for waiting)
   - Project name (current directory)
   - Git branch (auto-detected)
   - Timestamp

## Prerequisites

1. **Subscribe first** — In Feishu, send to the bot: `订阅CMUX`
2. **Verify target** — Run `bash ~/.openclaw/skills/cmux/scripts/cmux-subscribe.sh status` to confirm the target chat_id is set

## Advanced: Include Terminal ID

If you want the notification to show which cmux terminal/workspace triggered it, you can pass additional flags:

```json
{
  "type": "command",
  "command": "bash ~/.openclaw/skills/cmux/scripts/cmux-notify-feishu.sh --status waiting --workspace \"codex\" --terminal-id \"3-1\" --project \"$(basename $(pwd))\" \"Agent 等待指令\""
}
```

## Testing

Test the notification manually:

```bash
bash ~/.openclaw/skills/cmux/scripts/cmux-notify-feishu.sh \
  --status waiting \
  --workspace "test-workspace" \
  --project "MyProject" \
  "Test notification from cmux"
```

You should receive a message in Feishu if subscribed.
