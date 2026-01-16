# AgentNotch Claude Code Hooks

These hooks enable accurate notification detection in AgentNotch by using Claude Code's native hook system instead of time-based heuristics.

## Installation

### 1. Make the hook script executable

```bash
chmod +x /path/to/agentnotch/hooks/agentnotch-hook.sh
```

### 2. Add hooks to your Claude Code settings

Add this to your `~/.claude/settings.json` (global) or `.claude/settings.json` (project):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/agentnotch/hooks/agentnotch-hook.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo '{\"notification_type\":\"stop\",\"cwd\":\"'\"$PWD\"'\"}' | nc -U /tmp/agentnotch.sock 2>/dev/null; exit 0"
          }
        ]
      }
    ]
  }
}
```

Or use this inline version without the separate script (recommended):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "cat | nc -w 1 -U /tmp/agentnotch.sock 2>/dev/null; exit 0"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo '{\"notification_type\":\"stop\",\"cwd\":\"'\"$PWD\"'\"}' | nc -w 1 -U /tmp/agentnotch.sock 2>/dev/null; exit 0"
          }
        ]
      }
    ]
  }
}
```

**Note:** The `-w 1` flag sets a 1-second timeout to ensure `nc` doesn't hang.

## How It Works

1. When Claude Code needs user input (permission prompt, idle prompt), it triggers a `Notification` hook
2. The hook sends the notification JSON to AgentNotch via Unix domain socket at `/tmp/agentnotch.sock`
3. AgentNotch receives the notification and shows the visual/audio alert immediately
4. When Claude finishes (`Stop` hook), the permission state is cleared

## Notification Types

Claude Code sends these notification types:

- `permission_prompt` - Claude needs permission to run a tool
- `idle_prompt` - Claude is waiting for user input (after 60s idle)
- `auth_success` - Authentication completed
- `elicitation_dialog` - MCP tool needs input

## Troubleshooting

### Socket not found

If notifications aren't working, check that AgentNotch is running and the socket exists:

```bash
ls -la /tmp/agentnotch.sock
```

### Test the socket manually

```bash
echo '{"notification_type":"permission_prompt","cwd":"/tmp","message":"Test"}' | nc -U /tmp/agentnotch.sock
```

You should see the notification appear in AgentNotch.
