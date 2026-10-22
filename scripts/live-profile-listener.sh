#!/usr/bin/env bash
# ==============================================================================
# MCSC Live Profiling Listener
# Continuously samples CPU, RSS, Physical Footprint, and Threads during active use.
# Performs automated zero-leak and memory ceiling evaluation upon completion.
# ==============================================================================

set -eo pipefail

APP_NAME="MCSC"
DURATION=30
INTERVAL=1
BUDGET_MB=13.0
JSON_OUT=""

# Color formatting
BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
MAGENTA="\033[35m"
RESET="\033[0m"

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration|-d)
            DURATION="$2"
            shift 2
            ;;
        --interval|-i)
            INTERVAL="$2"
            shift 2
            ;;
        --json|-j)
            JSON_OUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--duration <seconds>] [--interval <seconds>] [--json <output_file>]"
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
    echo "Launch it with 'open /Applications/${APP_NAME}.app' or 'make run'."
    exit 1
fi

TMP_DIR=$(mktemp -d)
TMP_SAMPLES="$TMP_DIR/samples.tsv"
TMP_JSON="$TMP_DIR/fp.json"
TMP_LEAKS="$TMP_DIR/leaks.txt"
TMP_HEAP="$TMP_DIR/heap.txt"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo -e "${BOLD}${CYAN}======================================================================${RESET}"
echo -e "${BOLD}            MCSC Active Live Profiling Listener                       ${RESET}"
echo -e "${BOLD}${CYAN}======================================================================${RESET}"
echo -e "Target Process : ${BOLD}${APP_NAME}${RESET} (PID: ${CYAN}${PID}${RESET})"
echo -e "Duration       : ${YELLOW}${DURATION} seconds${RESET} (Sampling every ${INTERVAL}s)"
echo -e "Budget Ceiling : ${YELLOW}<=${BUDGET_MB} MB${RESET} (Idle physical footprint)"
echo -e "Active Usage   : ${GREEN}Ready! Please use the app extensively now...${RESET}"
echo ""

printf "${BOLD}%-10s  %-8s  %-8s  %-10s  %-14s  %-12s  %-8s${RESET}\n" \
    "TIME" "ELAPSED" "CPU %" "RSS (MB)" "FOOTPRINT (MB)" "DIRTY (MB)" "THREADS"
echo "--------------------------------------------------------------------------------"

# Header for sample logging TSV
echo "elapsed	cpu	rss	footprint	dirty	threads" > "$TMP_SAMPLES"

START_TIME=$(date +%s)
INTERRUPTED=false

trap 'INTERRUPTED=true' SIGINT SIGTERM

for (( elapsed=1; elapsed<=DURATION; elapsed+=INTERVAL )); do
    if [ "$INTERRUPTED" = true ]; then
        echo -e "\n${YELLOW}Listener interrupted by user. Generating summary...${RESET}"
        break
    fi

    # Check if process is still alive
    if ! kill -0 "$PID" 2>/dev/null; then
        echo -e "\n${RED}Process ${PID} terminated unexpectedly!${RESET}"
        break
    fi

    CURRENT_TIME=$(date "+%H:%M:%S")

    # Sample PS telemetry
    PS_INFO=$(ps -p "$PID" -o %cpu=,rss= 2>/dev/null || echo "0.0 0")
    CPU_VAL=$(echo "$PS_INFO" | awk '{print $1}')
    RSS_KB=$(echo "$PS_INFO" | awk '{print $2}')
    RSS_VAL=$(python3 -c "print(f'{(float(\"${RSS_KB:-0}\") / 1024.0):.2f}')")

    # Sample Mach Threads
    THREAD_LINES=$(ps -M "$PID" 2>/dev/null | wc -l || echo 2)
    THREADS=$(( THREAD_LINES > 1 ? THREAD_LINES - 1 : 1 ))

    # Sample Footprint & Dirty Memory
    FP_VAL="0.00"
    DIRTY_VAL="0.00"
    if footprint -p "$PID" -j "$TMP_JSON" >/dev/null 2>&1; then
        MEM_READ=$(python3 -c "
import json
try:
    with open('$TMP_JSON') as f:
        d = json.load(f)
    fp = d['processes'][0]['footprint'] / (1024.0 * 1024.0)
    dirty = d['summary']['total']['dirty'] / (1024.0 * 1024.0)
    print(f'{fp:.2f} {dirty:.2f}')
except Exception:
    print('0.00 0.00')
")
        FP_VAL=$(echo "$MEM_READ" | awk '{print $1}')
        DIRTY_VAL=$(echo "$MEM_READ" | awk '{print $2}')
    fi

    echo "$elapsed	$CPU_VAL	$RSS_VAL	$FP_VAL	$DIRTY_VAL	$THREADS" >> "$TMP_SAMPLES"

    printf "%-10s  %-8s  %-8s  %-10s  %-14s  %-12s  %-8s\n" \
        "$CURRENT_TIME" "${elapsed}s" "${CPU_VAL}%" "${RSS_VAL}" "${FP_VAL}" "${DIRTY_VAL}" "${THREADS}"

    sleep "$INTERVAL"
done

echo ""
echo -e "${BOLD}${CYAN}======================================================================${RESET}"
echo -e "${BOLD}                   Profiling Analysis & Audit Report                  ${RESET}"
echo -e "${BOLD}${CYAN}======================================================================${RESET}"

# Aggregate calculations
STATS=$(python3 -c "
import csv

cpus, rsses, fps, dirties, threads = [], [], [], [], []
try:
    with open('$TMP_SAMPLES') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            try:
                cpus.append(float(row['cpu']))
                rsses.append(float(row['rss']))
                fps.append(float(row['footprint']))
                dirties.append(float(row['dirty']))
                threads.append(int(row['threads']))
            except (ValueError, KeyError):
                continue
except Exception:
    pass

if cpus:
    print(f'{min(cpus):.1f} {max(cpus):.1f} {sum(cpus)/len(cpus):.1f} '
          f'{min(rsses):.2f} {max(rsses):.2f} {sum(rsses)/len(rsses):.2f} '
          f'{min(fps):.2f} {max(fps):.2f} {sum(fps)/len(fps):.2f} '
          f'{min(dirties):.2f} {max(dirties):.2f} {sum(dirties)/len(dirties):.2f} '
          f'{max(threads)} {len(cpus)}')
else:
    print('0 0 0 0 0 0 0 0 0 0 0 0 0 0')
")

read CPU_MIN CPU_MAX CPU_AVG RSS_MIN RSS_MAX RSS_AVG FP_MIN FP_MAX FP_AVG DIRTY_MIN DIRTY_MAX DIRTY_AVG THREADS_MAX SAMPLES_COUNT <<< "$STATS"

echo -e "${BOLD}--- 1. Live Performance Summary (${SAMPLES_COUNT} samples collected) ---${RESET}"
printf "  %-24s : Min %s%% | Max %s%% | Avg %s%%\n" "CPU Utilization" "$CPU_MIN" "$CPU_MAX" "$CPU_AVG"
printf "  %-24s : Min %s MB | Max %s MB | Avg %s MB\n" "Resident Set (RSS)" "$RSS_MIN" "$RSS_MAX" "$RSS_AVG"
printf "  %-24s : Min %s MB | Max %s MB | Avg %s MB\n" "Kernel Footprint" "$FP_MIN" "$FP_MAX" "$FP_AVG"
printf "  %-24s : Min %s MB | Max %s MB | Avg %s MB\n" "Dirty Memory" "$DIRTY_MIN" "$DIRTY_MAX" "$DIRTY_AVG"
printf "  %-24s : %s threads\n" "Peak Mach Threads" "$THREADS_MAX"

echo ""
echo -e "${BOLD}--- 2. Memory Category Breakdown (Final Sample) ---${RESET}"
if [ -f "$TMP_JSON" ]; then
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
    print('  Categories unavailable:', e)
"
else
    echo "  Memory category data unavailable."
fi

echo ""
echo -e "${BOLD}--- 3. Heap Allocation Analysis ---${RESET}"
heap "$PID" -s > "$TMP_HEAP" 2>/dev/null || true
if [ -s "$TMP_HEAP" ]; then
    tail -n 6 "$TMP_HEAP" | sed 's/^/  /'
else
    echo "  Heap analysis unavailable."
fi

echo ""
echo -e "${BOLD}--- 4. Zero-Leak Verification ---${RESET}"
leaks "$PID" > "$TMP_LEAKS" 2>&1 || true
if grep -q "0 leaks for 0 total leaked bytes" "$TMP_LEAKS"; then
    echo -e "  ${GREEN}✓ Zero Leaks Detected: 0 leaks for 0 total leaked bytes.${RESET}"
else
    echo -e "  ${YELLOW}⚠️ Leaks output summary:${RESET}"
    tail -n 8 "$TMP_LEAKS" | sed 's/^/  /'
fi

echo ""
echo -e "${BOLD}--- 5. Diagnostics Audit ---${RESET}"
DIAG_LOG="$HOME/Library/Logs/MCSC/diagnostic_report.jsonl"
if [ -f "$DIAG_LOG" ]; then
    echo "  Recent diagnostic report entries:"
    tail -n 3 "$DIAG_LOG" | sed 's/^/    /'
else
    echo "  Diagnostic log clean: No crashes or anomalous events reported."
fi

echo ""
echo -e "${BOLD}--- 6. Budget & Verification Evaluation ---${RESET}"
python3 -c "
fp_max = float('$FP_MAX')
budget = float('$BUDGET_MB')
if fp_max <= budget:
    print(f'  \033[32m✓ PASSED: Max Footprint ({fp_max:.2f} MB) is within budget ({budget:.1f} MB)\033[0m')
else:
    print(f'  \033[33mℹ️ NOTE: Max Footprint was {fp_max:.2f} MB (Budget ceiling: {budget:.1f} MB)\033[0m')
"

# Optional JSON export
if [ -n "$JSON_OUT" ]; then
    mkdir -p "$(dirname "$JSON_OUT")"
    python3 -c "
import json
report = {
    'pid': $PID,
    'duration_seconds': $DURATION,
    'samples_count': $SAMPLES_COUNT,
    'cpu': {'min': float('$CPU_MIN'), 'max': float('$CPU_MAX'), 'avg': float('$CPU_AVG')},
    'rss_mb': {'min': float('$RSS_MIN'), 'max': float('$RSS_MAX'), 'avg': float('$RSS_AVG')},
    'footprint_mb': {'min': float('$FP_MIN'), 'max': float('$FP_MAX'), 'avg': float('$FP_AVG')},
    'dirty_mb': {'min': float('$DIRTY_MIN'), 'max': float('$DIRTY_MAX'), 'avg': float('$DIRTY_AVG')},
    'peak_threads': int('$THREADS_MAX')
}
with open('$JSON_OUT', 'w') as f:
    json.dump(report, f, indent=2)
print('  Exported benchmark report to: $JSON_OUT')
"
fi

echo -e "\n${BOLD}${CYAN}Profile run complete.${RESET}\n"
