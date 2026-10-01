#!/bin/zsh

# ==============================================================================
# ⚠️ SAFETY DIRECTIVE FOR AI AGENTS AND AUTOMATION:
# THIS IS A REGULAR USER MACHINE, NOT A DISPOSABLE TEST SANDBOX.
#
# RULE 1: AI AGENTS MUST NEVER EXECUTE DESTRUCTIVE ACTIONS (E.G. KEYBOARD SHORTCUTS
#         LIKE Cmd+W, Cmd+Q, OR WINDOW CLOSING GESTURES) WITHOUT ASKING AND RECEIVING
#         EXPLICIT PRIOR CONFIRMATION FROM THE DEVELOPER.
# RULE 2: NEVER INJECT REAL CLOSE/QUIT EVENTS WHILE OTHER USER APPS HAVE UNSAVED WORK.
# ==============================================================================

set -e

COMMAND="${1:-help}"

case "$COMMAND" in
    check)
        echo "=== MCSC Health Check ==="
        PID=$(pgrep -x "MCSC" | head -n 1)
        if [ -n "$PID" ]; then
            echo "✅ MCSC is running (PID: $PID)"
            ps -p "$PID" -o pid,%cpu,%mem,command
        else
            echo "❌ MCSC is not running."
            exit 1
        fi
        ;;

    state)
        echo "=== MCSC Live State ==="
        "$(dirname "$0")/dump-state.sh"
        ;;

    test-mc-start)
        echo "Posting non-destructive Mission Control start notification..."
        # Simulates Dock notification without disrupting open windows
        python3 -c "
import Foundation
center = Foundation.NSDistributedNotificationCenter.defaultCenter()
center.postNotificationName_object_('com.apple.expose.start', None)
"
        echo "Notification posted. Inspect with ./scripts/stream-logs.sh or ./scripts/dump-state.sh."
        ;;

    test-mc-stop)
        echo "Posting non-destructive Mission Control stop notification..."
        python3 -c "
import Foundation
center = Foundation.NSDistributedNotificationCenter.defaultCenter()
center.postNotificationName_object_('com.apple.expose.stop', None)
"
        echo "Notification posted."
        ;;

    inject-key)
        KEY="${2:-}"
        CONFIRM="${3:-}"

        if [ "$CONFIRM" != "--confirm-destructive" ]; then
            echo "🛑 SAFETY INTERLOCK BLOCKED OPERATION!"
            echo "You are attempting to inject a keystroke ('$KEY') into the user session."
            echo "On a regular machine, this can close active tabs, windows, or quit applications."
            echo ""
            echo "AI AGENTS: YOU MUST STOP AND ASK THE DEVELOPER FOR EXPLICIT PERMISSION BEFORE PROCEEDING."
            echo "To bypass, re-run with: $0 inject-key <key> --confirm-destructive"
            exit 2
        fi

        echo "⚠️ Executing confirmed keystroke injection: $KEY"
        osascript -e "tell application \"System Events\" to keystroke \"$KEY\""
        ;;

    help|*)
        echo "MCSC Safe Developer & AI Diagnostic CLI"
        echo ""
        echo "Usage:"
        echo "  $0 check            - Verify process health (safe)"
        echo "  $0 state            - Inspect internal live state (safe)"
        echo "  $0 test-mc-start    - Post Mission Control enter notification (safe)"
        echo "  $0 test-mc-stop     - Post Mission Control exit notification (safe)"
        echo "  $0 inject-key <key> --confirm-destructive - Injects key (REQUIRES USER CONFIRMATION)"
        ;;
esac
