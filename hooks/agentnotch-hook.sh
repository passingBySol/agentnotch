#!/bin/bash
# AgentNotch notification hook for Claude Code
# This script receives notification JSON via stdin and sends it to the AgentNotch socket

SOCKET_PATH="/tmp/agentnotch.sock"

# Read stdin (notification JSON from Claude Code)
notification=$(cat)

# Check if socket exists
if [ -S "$SOCKET_PATH" ]; then
    # Send notification to AgentNotch via Unix socket
    echo "$notification" | nc -U "$SOCKET_PATH" 2>/dev/null
fi

# Always exit successfully so we don't block Claude Code
exit 0
