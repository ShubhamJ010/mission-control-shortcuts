#!/bin/zsh

# stream-logs.sh
# Streams Apple Unified Logging output for MCSC in real time.
# Read-only and non-destructive. Completely safe for regular developer machines.

SUBSYSTEM="sj010.MCSC"
CATEGORY="${1:-}"

echo "Streaming logs for subsystem: $SUBSYSTEM (Press Ctrl+C to stop)..."

if [ -n "$CATEGORY" ]; then
    echo "Filtering by category: $CATEGORY"
    log stream --predicate "subsystem == \"$SUBSYSTEM\" AND category == \"$CATEGORY\"" --level debug --style compact
else
    log stream --predicate "subsystem == \"$SUBSYSTEM\"" --level debug --style compact
fi
