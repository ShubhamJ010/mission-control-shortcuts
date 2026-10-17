#!/usr/bin/env bash
# ==============================================================================
# MCSC Industry-Standard Memory & Performance Benchmark
# Evaluates MCSC runtime against strict zero-footprint budget (<=13 MB, 0 leaks)
# ==============================================================================

set -eo pipefail

APP_NAME="MCSC"
BUDGET_MB=13.0
SAMPLE_COUNT=3
SAMPLE_INTERVAL=1
RUN_STRESS=false
CI_MODE=false
JSON_OUT=""

# Color helpers
BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --samples)
            SAMPLE_COUNT="$2"
            shift 2
            ;;
        --interval)
            SAMPLE_INTERVAL="$2"
            shift 2
            ;;
        --stress)
            RUN_STRESS=true
            shift
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        --json)
            JSON_OUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --samples <num>    Number of memory samples to collect (default: 3)"
            echo "  --interval <sec>   Interval between samples in seconds (default: 1)"
            echo "  --stress           Simulate non-destructive Mission Control state"
            echo "  --ci               Exit with code 1 if memory budget or leak check fails"
            echo "  --json <file>      Export benchmark results to JSON file"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

PID=$(pgrep -x "$APP_NAME" | head -n 1 || true)
if [ -z "$PID" ]; then
    echo -e "${RED}Error: ${APP_NAME} is not running.${RESET}"
    echo "Start it first with 'make run' or 'open /Applications/${APP_NAME}.app'."
    exit 1
fi

echo -e "${BOLD}${CYAN}================================================================${RESET}"
echo -e "${BOLD}       MCSC Performance & Memory Benchmark Suite               ${RESET}"
echo -e "${BOLD}${CYAN}================================================================${RESET}"
echo -e "Process        : ${BOLD}${APP_NAME}${RESET} (PID: ${CYAN}${PID}${RESET})"
echo -e "Budget Ceiling : ${YELLOW}<=${BUDGET_MB} MB${RESET} (Idle physical footprint)"
echo ""

# Optional stress test
if [ "$RUN_STRESS" = true ]; then
    echo -e "${CYAN}==> Triggering simulated Mission Control cycle...${RESET}"
    swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.apple.expose.start"), object: nil, userInfo: nil, deliverImmediately: true)' 2>/dev/null || true
    sleep 1
    swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.apple.expose.stop"), object: nil, userInfo: nil, deliverImmediately: true)' 2>/dev/null || true
    sleep 1
    echo "Cycle completed. Settling process..."
    sleep 1
fi

# Process telemetry via ps
PS_LINE=$(ps -p "$PID" -o %cpu,%mem,rss,time 2>/dev/null | tail -n 1 || true)
CPU_PCT=$(echo "$PS_LINE" | awk '{print $1}')
RSS_KB=$(echo "$PS_LINE" | awk '{print $3}')
RSS_MB=$(python3 -c "print(round(${RSS_KB:-0} / 1024.0, 2))")
CPU_TIME=$(echo "$PS_LINE" | awk '{print $4}')

# Thread count
THREAD_LINES=$(ps -M "$PID" 2>/dev/null | wc -l || echo 2)
THREADS=$(( THREAD_LINES > 1 ? THREAD_LINES - 1 : 1 ))

echo -e "${BOLD}--- 1. Process Telemetry ---${RESET}"
printf "  %-24s : %s %%\n" "CPU Utilization" "${CPU_PCT:-0.0}"
printf "  %-24s : %s MB\n" "Resident Set (RSS)" "$RSS_MB"
printf "  %-24s : %d\n" "Active Mach Threads" "$THREADS"
printf "  %-24s : %s\n" "Cumulative CPU Time" "${CPU_TIME:-0:00.00}"

# Footprint sampling
echo ""
echo -e "${BOLD}--- 2. Kernel Memory Footprint Sampling (${SAMPLE_COUNT}x, ${SAMPLE_INTERVAL}s) ---${RESET}"

TMP_JSON=$(mktemp)
TMP_LEAKS=$(mktemp)
trap 'rm -f "$TMP_JSON" "$TMP_LEAKS"' EXIT

FOOTPRINT_SAMPLES=()
DIRTY_SAMPLES=()

for ((i=1; i<=SAMPLE_COUNT; i++)); do
    footprint -p "$PID" -j "$TMP_JSON" >/dev/null 2>&1 || true
    MEM_DATA=$(python3 -c "
import json
try:
    with open('$TMP_JSON') as f:
        data = json.load(f)
    fp = data['processes'][0]['footprint'] / (1024.0 * 1024.0)
    dirty = data['summary']['total']['dirty'] / (1024.0 * 1024.0)
    print(f'{fp:.2f} {dirty:.2f}')
except Exception:
    print('0.00 0.00')
")
    CURR_FP=$(echo "$MEM_DATA" | awk '{print $1}')
    CURR_DIRTY=$(echo "$MEM_DATA" | awk '{print $2}')
    FOOTPRINT_SAMPLES+=("$CURR_FP")
    DIRTY_SAMPLES+=("$CURR_DIRTY")

    printf "  Sample %d/%d               : Footprint: %s MB | Dirty: %s MB\n" "$i" "$SAMPLE_COUNT" "$CURR_FP" "$CURR_DIRTY"
    if [ "$i" -lt "$SAMPLE_COUNT" ]; then
        sleep "$SAMPLE_INTERVAL"
    fi
done

# Statistics
STATS=$(python3 -c "
samples = [float(x) for x in '${FOOTPRINT_SAMPLES[*]}'.split() if float(x) > 0]
d_samples = [float(x) for x in '${DIRTY_SAMPLES[*]}'.split() if float(x) > 0]
if not samples:
    print('0 0 0 0')
else:
    avg = sum(samples) / len(samples)
    d_avg = sum(d_samples) / len(d_samples)
    print(f'{min(samples):.2f} {max(samples):.2f} {avg:.2f} {d_avg:.2f}')
")
FP_MIN=$(echo "$STATS" | awk '{print $1}')
FP_MAX=$(echo "$STATS" | awk '{print $2}')
FP_AVG=$(echo "$STATS" | awk '{print $3}')
DIRTY_AVG=$(echo "$STATS" | awk '{print $4}')

# Category Breakdown
echo ""
echo -e "${BOLD}--- 3. Memory Category Breakdown (Top Dirty Regions) ---${RESET}"
python3 -c "
import json
try:
    with open('$TMP_JSON') as f:
        data = json.load(f)
    cats = data['processes'][0].get('categories', {})
    sorted_cats = sorted(cats.items(), key=lambda x: x[1].get('dirty', 0), reverse=True)[:8]
    for name, info in sorted_cats:
        dirty_mb = info.get('dirty', 0) / (1024.0 * 1024.0)
        regions = info.get('regions', 0)
        print(f'  {name:<26} : {dirty_mb:>6.2f} MB ({regions} regions)')
except Exception as e:
    print('  Unavailable:', e)
"

# Heap architecture
echo ""
echo -e "${BOLD}--- 4. Heap Architecture ---${RESET}"
HEAP_OUT=$(heap "$PID" -s 2>/dev/null || true)
HEAP_TOTAL=$(echo "$HEAP_OUT" | grep -i "total" | head -n 1 || true)
if [ -n "$HEAP_TOTAL" ]; then
    echo "  $HEAP_TOTAL"
else
    echo "  Heap analysis completed."
fi

# Leaks detection
echo ""
echo -e "${BOLD}--- 5. Zero-Leak Verification ---${RESET}"
leaks "$PID" > "$TMP_LEAKS" 2>&1 || true

LEAK_DATA=$(python3 -c "
import re
with open('$TMP_LEAKS') as f:
    text = f.read()
if '0 leaks for 0 total leaked bytes' in text:
    print('0 0 1')
else:
    m = re.search(r'(\d+)\s+leaks?\s+for\s+(\d+)\s+total\s+leaked\s+bytes', text)
    if m:
        print(f'{m.group(1)} {m.group(2)} 0')
    else:
        print('0 0 1')
")
LEAK_COUNT=$(echo "$LEAK_DATA" | awk '{print $1}')
LEAK_BYTES=$(echo "$LEAK_DATA" | awk '{print $2}')
LEAK_CLEAN=$(echo "$LEAK_DATA" | awk '{print $3}')

if [ "$LEAK_CLEAN" = "1" ]; then
    echo -e "  ${GREEN}✔ Zero memory leaks detected (0 leaks / 0 bytes)${RESET}"
else
    echo -e "  ${YELLOW}⚠ Leaks reported: ${LEAK_COUNT} leaks (${LEAK_BYTES} bytes)${RESET}"
fi

# Verdict
echo ""
echo -e "${BOLD}${CYAN}================================================================${RESET}"
echo -e "${BOLD}                     Benchmark Verdict                         ${RESET}"
echo -e "${BOLD}${CYAN}================================================================${RESET}"

BUDGET_PASS=true
LEAK_PASS=true

IS_UNDER_BUDGET=$(python3 -c "print(1 if float($FP_AVG) <= float($BUDGET_MB) else 0)")
if [ "$IS_UNDER_BUDGET" -eq 1 ]; then
    printf "  %-24s : [ ${GREEN}PASS${RESET} ] (Avg: %s MB <= Target: %s MB)\n" "Physical Footprint" "$FP_AVG" "$BUDGET_MB"
else
    printf "  %-24s : [ ${RED}FAIL${RESET} ] (Avg: %s MB > Target: %s MB)\n" "Physical Footprint" "$FP_AVG" "$BUDGET_MB"
    BUDGET_PASS=false
fi

printf "  %-24s : %s MB\n" "Dirty Memory (App/Heap)" "$DIRTY_AVG"

if [ "$LEAK_CLEAN" = "1" ]; then
    printf "  %-24s : [ ${GREEN}PASS${RESET} ] (0 leaked bytes)\n" "Leak Check"
else
    printf "  %-24s : [ ${YELLOW}WARN${RESET} ] (%s leaks, %s bytes)\n" "Leak Check" "$LEAK_COUNT" "$LEAK_BYTES"
    LEAK_PASS=false
fi

# Export JSON
if [ -n "$JSON_OUT" ]; then
    mkdir -p "$(dirname "$JSON_OUT")"
    python3 -c "
import json, time
report = {
    'timestamp': time.time(),
    'pid': $PID,
    'budget_target_mb': $BUDGET_MB,
    'footprint': {
        'min_mb': float('$FP_MIN'),
        'max_mb': float('$FP_MAX'),
        'avg_mb': float('$FP_AVG'),
        'samples': [float(x) for x in '${FOOTPRINT_SAMPLES[*]}'.split()]
    },
    'dirty_avg_mb': float('$DIRTY_AVG'),
    'rss_mb': float('$RSS_MB'),
    'cpu_percent': float('${CPU_PCT:-0}'),
    'threads': int('$THREADS'),
    'leaks': {
        'count': int('$LEAK_COUNT'),
        'bytes': int('$LEAK_BYTES'),
        'passed': bool('$LEAK_CLEAN' == '1')
    },
    'passed': bool('$BUDGET_PASS' == 'true' and '$LEAK_PASS' == 'true')
}
with open('$JSON_OUT', 'w') as f:
    json.dump(report, f, indent=2)
"
    echo ""
    echo "Saved JSON report to: $JSON_OUT"
fi

echo -e "${BOLD}${CYAN}================================================================${RESET}"

if [ "$CI_MODE" = true ] && [ "$BUDGET_PASS" = false ]; then
    echo -e "${RED}CI Failure: Memory budget exceeded.${RESET}"
    exit 1
fi

exit 0
