#!/bin/zsh

# dump-state.sh
# Non-destructive on-demand live state inspection via SIGUSR1.
# Safe to run anytime on regular machines without interrupting user apps.

set -e

PID=$(pgrep -x "MCSC" | head -n 1)

if [ -z "$PID" ]; then
    echo "MCSC is not running."
    exit 1
fi

echo "Requesting live state from MCSC (PID: $PID)..."
kill -USR1 "$PID"

# Give the main thread a moment to write the atomic JSON file
sleep 0.2

STATE_FILE="/tmp/mcsc-live.json"
if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
    echo "\nLive state written to: $STATE_FILE"
else
    echo "Error: State file was not generated."
    exit 1
fi
