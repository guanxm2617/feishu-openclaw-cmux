# feishu-openclaw-cmux

CMUX skill files for controlling cmux from Feishu and forwarding CMUX/agent notifications back to Feishu.

## Contents

- `SKILL.md` — skill definition and command patterns
- `scripts/` — helper scripts for cmux execution, reading output, subscriptions, and Feishu notification forwarding
- `hooks/` — Claude Code hook examples

## Included capabilities

- List CMUX workspaces and panes
- Send commands to CMUX panes
- Auto-read recent terminal output after command execution
- Manually read terminal output
- Subscribe/unsubscribe CMUX notification forwarding to Feishu

## Notes

This repository intentionally excludes local runtime state such as `state.json` and macOS metadata files.
