#!/bin/zsh

# trace-signposts.sh
# Records 5 seconds of AppSignpost activity via xctrace CLI.
# Read-only and non-destructive. Completely safe for regular developer machines.

set -e

PID=$(pgrep -x "MCSC" | head -n 1)

if [ -z "$PID" ]; then
    echo "MCSC is not running. Please launch the app first."
    exit 1
fi

DURATION="${1:-5}"
TRACE_FILE="/tmp/mcsc_signposts.trace"

rm -rf "$TRACE_FILE"

echo "Recording $DURATION seconds of signpost activity for MCSC (PID: $PID)..."
echo "Trace file: $TRACE_FILE"

xctrace record \
    --template 'Points of Interest' \
    --attach "$PID" \
    --time-limit "${DURATION}s" \
    --output "$TRACE_FILE"

echo "Trace recording complete: $TRACE_FILE"
echo "To view, open in Xcode Instruments or run: xctrace export --input $TRACE_FILE"
