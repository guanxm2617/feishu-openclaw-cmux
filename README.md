# CMUX 飞书集成工具

通过飞书消息远程控制 CMUX 终端，并将 CMUX 原生通知转发到飞书会话。

## 简介

[CMUX](https://github.com/cmux/cmux) 是一个基于 Ghostty 的 macOS 终端，专为 AI 编程助手设计。本项目提供了一套脚本工具，实现双向集成：

- **飞书 → CMUX**：通过飞书消息发送命令，远程控制终端
- **CMUX → 飞书**：将 CMUX 原生通知（任务完成、等待输入等）自动推送到飞书

## 项目结构

```
.
├── SKILL.md              # OpenClaw Skill 定义（完整命令参考）
├── README.md             # 本文件
├── scripts/              # 核心脚本
│   ├── cmux-send.sh          # CMUX Socket 通信基础脚本
│   ├── cmux-list-all.sh      # 列出所有工作区和面板
│   ├── cmux-exec.sh          # 发送命令并自动读取输出
│   ├── cmux-read.sh          # 手动读取终端输出
│   ├── cmux-subscribe.sh     # 订阅/取消订阅通知转发
│   ├── cmux-daemon.sh        # 后台通知轮询守护进程
│   ├── cmux-notify-feishu.sh # 发送通知到飞书
│   ├── state.sh              # 状态管理（JSON 文件锁）
│   └── feishu-send-card.mjs  # 飞书卡片消息发送
└── hooks/                # Claude Code Hook 示例
    └── claude-code-hooks.md
```

## 核心功能

### 1. 远程终端控制

通过飞书消息控制 CMUX 终端，支持：

- 📋 列出所有工作区和面板
- 📤 发送命令到指定终端
- 👁️ 读取终端输出（自动/手动）
- 🔄 切换工作区

### 2. 通知自动转发

订阅后，后台守护进程每 4 秒检查一次 CMUX 原生通知，将新通知自动推送到飞书：

| 状态 | 说明 | 图标 |
|------|------|------|
| completed | 任务完成 | ✅ |
| waiting | 等待用户输入 | ⏳ |
| error | 执行出错 | ❌ |
| started | 任务开始 | 🚀 |

## 快速开始

### 前提条件

- macOS（CMUX 仅支持 macOS）
- CMUX 应用已运行
- 已安装 `netcat`：`brew install netcat`
- 已配置 OpenClaw 飞书通道

### 安装

```bash
# 克隆到 OpenClaw skills 目录
git clone https://github.com/guanxm2617/feishu-openclaw-cmux.git \
  ~/.openclaw/skills/cmux

# 赋予脚本执行权限
chmod +x ~/.openclaw/skills/cmux/scripts/*.sh
```

### 基础用法

#### 列出工作区和面板

```bash
bash ~/.openclaw/skills/cmux/scripts/cmux-list-all.sh
```

#### 发送命令到终端

```bash
# 发送命令并自动回读输出（等待 3 秒）
bash ~/.openclaw/skills/cmux/scripts/cmux-exec.sh 3-1 "git status"

# 配置等待时间和读取行数
CMUX_EXEC_WAIT=5 CMUX_EXEC_READ_LINES=30 \
  bash ~/.openclaw/skills/cmux/scripts/cmux-exec.sh 3-1 "npm test"
```

#### 手动读取终端输出

```bash
# 读取最近 50 行（默认）
bash ~/.openclaw/skills/cmux/scripts/cmux-read.sh 3-1

# 读取指定行数
bash ~/.openclaw/skills/cmux/scripts/cmux-read.sh 3-1 100
bash ~/.openclaw/skills/cmux/scripts/cmux-read.sh 3-1 最近100行
bash ~/.openclaw/skills/cmux/scripts/cmux-read.sh 3-1 全部
```

#### 订阅通知转发

```bash
# 开始订阅（启动后台守护进程）
bash ~/.openclaw/skills/cmux/scripts/cmux-subscribe.sh subscribe

# 查看订阅状态
bash ~/.openclaw/skills/cmux/scripts/cmux-subscribe.sh status

# 取消订阅（停止守护进程）
bash ~/.openclaw/skills/cmux/scripts/cmux-subscribe.sh unsubscribe
```

#### 手动发送通知

```bash
CMUX_FEISHU_TARGET="oc_xxxx" \
  bash ~/.openclaw/skills/cmux/scripts/cmux-notify-feishu.sh \
    --status completed \
    "任务已完成：重构认证模块"
```

## 飞书命令模式

在飞书中发送以下消息，机器人会自动识别并执行：

| 命令 | 触发词 | 说明 |
|------|--------|------|
| 列出工作区 | `列出cmux工作区`、`cmux列表`、`连接CMUX` | 显示所有工作区和面板 |
| 发送命令 | `cmux发送 <ID> <命令>` | 发送命令并返回执行结果 |
| 读取输出 | `cmux读取 <ID>`、`cmux读取 <ID> 最近N行` | 读取终端输出 |
| 订阅通知 | `订阅CMUX`、`开启CMUX通知` | 启动通知转发 |
| 取消订阅 | `取消订阅`、`关闭CMUX通知` | 停止通知转发 |
| 查看状态 | `CMUX订阅状态`、`订阅状态` | 显示订阅状态 |

> **注意**：`<ID>` 格式为 `工作区索引-面板索引`，如 `3-1` 表示第 3 个工作区的第 1 个面板。

## 配置选项

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CMUX_EXEC_WAIT` | 命令执行后等待时间（秒） | 3（最大 10） |
| `CMUX_EXEC_READ_LINES` | 自动读取行数 | 20（最大 50） |
| `CMUX_READ_DEFAULT_LINES` | 手动读取默认行数 | 50 |
| `CMUX_READ_MAX_LINES` | 手动读取最大行数 | 200 |
| `CMUX_DAEMON_POLL` | 通知轮询间隔（秒） | 4 |
| `CMUX_DAEMON_MAX_SEEN` | 已读通知 ID 保留数量 | 200 |
| `CMUX_FEISHU_TARGET` | 飞书目标会话 ID | - |

### Claude Code Hook 集成

在 `~/.claude/settings.json` 中添加 Hook，实现自动通知：

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CMUX_FEISHU_TARGET='oc_xxxx' bash ~/.openclaw/skills/cmux/scripts/cmux-notify-feishu.sh --status waiting 'Claude 正在等待您的输入'"
          }
        ]
      }
    ]
  }
}
```

## 故障排查

| 问题 | 解决方案 |
|------|----------|
| `cmux socket not found` | 确保 CMUX 应用正在运行 |
| `Failed to communicate` | 检查 Socket 权限：`ls -la "$HOME/Library/Application Support/cmux/"` |
| `nc: command not found` | 安装 netcat：`brew install netcat` |
| Socket 认证错误 | 打开 CMUX 设置 → Socket Control → 设置为 "Automation mode" 或 "Full open access" |
| 飞书发送失败 | 运行 `openclaw status` 检查飞书通道状态 |
| 通知转发不工作 | 检查守护进程状态：`cmux-subscribe.sh status` |

## 工作原理

### Socket 通信

CMUX 在 `$HOME/Library/Application Support/cmux/cmux.sock` 暴露 Unix Domain Socket，脚本通过 `cmux-send.sh` 与之通信。

### 通知转发机制

1. `cmux-daemon.sh` 后台进程每 4 秒轮询 `list_notifications`
2. 新通知通过 `cmux-notify-feishu.sh` 发送到飞书
3. 成功发送后才标记为已读（避免丢失通知）
4. 状态使用文件锁保护，支持并发安全写入

### 状态管理

用户主目录下的 `~/.openclaw/skills/cmux/state.json` 存储：
- 目标飞书会话 ID
- 订阅状态
- 守护进程 PID
- 已读通知 ID 列表

## 许可证

MIT
