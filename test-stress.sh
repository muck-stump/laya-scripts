#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi

# Configuration with defaults
NUM_REQUESTS="${1:-5}" # Number of requests, defaults to 5. Can be passed as first argument.

if [[ -n "${ENDPOINT:-}" ]]; then
  BASE_URL="https://${ENDPOINT}"
else
  HOST="${LAYA_HOST:-127.0.0.1}"
  PORT="${LAYA_PORT:-8000}"
  BASE_URL="http://${HOST}:${PORT}"
fi

AUTH_PATH="/v1/systemone"

AUTH_HEADER=()
if [[ -n "${API_KEY:-}" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${API_KEY}")
fi

if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  BLUE=''
  CYAN=''
  YELLOW=''
  BOLD=''
  NC=''
fi

PAYLOAD='{
  "model": "english",
  "state": "Payment gateway reports timeout on charge authorizations. Urgent.",
  "questions": {
    "intent": {
      "type": "choice",
      "instructions": "What is the operational nature of this ticket?",
      "criteria": {
        "payment_failure": "Failures processing charges, gateway timeouts",
        "access_issue": "Login, SSO, authentication, or permission errors"
      }
    },
    "is_urgent": {
      "type": "noul",
      "instructions": "Does the request require immediate intervention?"
    },
    "severity": {
      "type": "score",
      "instructions": "Rate incident severity.",
      "criteria": ["Low", "Medium", "High", "Critical"]
    }
  }
}'

get_time() {
  date +%s.%N
}

calculate_duration() {
  local start="$1"
  local end="$2"
  python3 -c "print(round($end - $start, 3))"
}

print_header() {
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "${BOLD}  LAYA-SERVER STRESS & PERFORMANCE TESTS${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "Target URL:      ${BOLD}$BASE_URL${NC}"
  echo -e "Endpoint:        ${BOLD}$AUTH_PATH${NC}"
  echo -e "Requests / Mode: ${BOLD}$NUM_REQUESTS${NC}"
  echo
}

print_header

# ----------------------------------------------------------------------
# Mode 1: Sequential Execution (Individual Curls One by One)
# ----------------------------------------------------------------------
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${BOLD}[1] SEQUENTIAL MODE (Individual curls, one after the other)${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo "Sending $NUM_REQUESTS requests sequentially..."

m1_start=$(get_time)
m1_success=0

for ((i=1; i<=NUM_REQUESTS; i++)); do
  echo -n "  Request #$i: "
  status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL$AUTH_PATH" \
    ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  
  if [[ "$status" == "200" ]]; then
    echo -e "${GREEN}PASS${NC} (got $status)"
    m1_success=$((m1_success + 1))
  else
    echo -e "${RED}FAIL${NC} (got $status)"
  fi
done

m1_end=$(get_time)
m1_duration=$(calculate_duration "$m1_start" "$m1_end")
m1_avg=$(python3 -c "print(round($m1_duration / $NUM_REQUESTS, 3))")

echo
echo -e "  Success Rate: ${BOLD}$m1_success / $NUM_REQUESTS${NC}"
echo -e "  Total Time:   ${BOLD}${m1_duration}s${NC}"
echo -e "  Avg Latency:  ${BOLD}${m1_avg}s / request${NC}"
echo

# ----------------------------------------------------------------------
# Mode 2: Concurrency Ramp (1 → NUM_REQUESTS, find the break point)
# ----------------------------------------------------------------------
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${BOLD}[2] CONCURRENCY RAMP (sweep from 1 to $NUM_REQUESTS concurrent requests)${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"

m2_duration="n/a"
m2_success=0
m2_last_n=0
declare -A ramp_results  # n -> "pass_count/n"

for ((n=1; n<=NUM_REQUESTS; n++)); do
  echo -n "  Concurrency $n: "
  tmp_dir=$(mktemp -d)
  pids=()
  ramp_start=$(get_time)

  for ((i=1; i<=n; i++)); do
    (
      body=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL$AUTH_PATH" \
        ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")
      status=$(echo "$body" | tail -n1)
      response=$(echo "$body" | head -n -1)
      echo "$status"   > "$tmp_dir/status_$i"
      echo "$response" > "$tmp_dir/body_$i"
    ) &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  ramp_end=$(get_time)
  ramp_dur=$(calculate_duration "$ramp_start" "$ramp_end")

  pass=0
  first_fail_body=""
  first_fail_status=""
  for ((i=1; i<=n; i++)); do
    s=$(cat "$tmp_dir/status_$i" 2>/dev/null || echo "failed")
    if [[ "$s" == "200" ]]; then
      pass=$((pass + 1))
    elif [[ -z "$first_fail_status" ]]; then
      first_fail_status="$s"
      first_fail_body=$(cat "$tmp_dir/body_$i" 2>/dev/null || echo "(no body)")
    fi
  done
  rm -rf "$tmp_dir"

  ramp_results[$n]="$pass/$n"

  if (( pass == n )); then
    echo -e "${GREEN}ALL PASS${NC} ($pass/$n) — ${ramp_dur}s"
    m2_success=$pass
    m2_last_n=$n
    m2_duration="${ramp_dur}s"
  else
    echo -e "${RED}FAILURES${NC} ($pass/$n) — ${ramp_dur}s"
    [[ -n "$first_fail_body" ]] && echo -e "    First failure: HTTP $first_fail_status — $first_fail_body"
    m2_last_n=$n
    m2_duration="${ramp_dur}s"
  fi
done

echo
echo -e "  Ramp results:"
for ((n=1; n<=NUM_REQUESTS; n++)); do
  printf "    Concurrency %-3s → %s\n" "$n" "${ramp_results[$n]}"
done
echo

# ----------------------------------------------------------------------
# Mode 3: Single Curl with Multiple Requests (Chained via --next)
# ----------------------------------------------------------------------
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${BOLD}[3] SINGLE CURL MODE (Chained sequentially via curl --next)${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo "Executing single curl command with $NUM_REQUESTS chained requests (connection reuse)..."

# Construct curl command with --next
cmd=("curl")
for ((i=1; i<=NUM_REQUESTS; i++)); do
  if (( i > 1 )); then
    cmd+=("--next")
  fi
  cmd+=(
    "-s"
    "-o" "/dev/null"
    "-w" "%{http_code}\n"
    "-X" "POST"
    "$BASE_URL$AUTH_PATH"
    ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"}
    "-H" "Content-Type: application/json"
    "-d" "$PAYLOAD"
  )
done

m3_start=$(get_time)
# Run the built command and read responses line by line
m3_success=0
m3_total=0

while read -r status; do
  if [[ -n "$status" ]]; then
    m3_total=$((m3_total + 1))
    if [[ "$status" == "200" ]]; then
      m3_success=$((m3_success + 1))
    fi
  fi
done < <( "${cmd[@]}" )

m3_end=$(get_time)
m3_duration=$(calculate_duration "$m3_start" "$m3_end")
m3_avg=$(python3 -c "print(round($m3_duration / $NUM_REQUESTS, 3))")

echo "  Chained request execution complete."
echo
echo -e "  Success Rate: ${BOLD}$m3_success / $m3_total${NC}"
echo -e "  Total Time:   ${BOLD}${m3_duration}s${NC}"
echo -e "  Avg Latency:  ${BOLD}${m3_avg}s / request${NC}"
echo

# ----------------------------------------------------------------------
# Overall Summary
# ----------------------------------------------------------------------
echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}  STRESS TEST COMPARISON SUMMARY${NC}"
echo -e "${CYAN}======================================================================${NC}"
printf "  %-25s %-15s %-15s\n" "Test Mode" "Total Time" "Success Rate"
echo -e "  --------------------------------------------------------------------"
printf "  %-25s %-15s %-15s\n" "Sequential Mode" "${m1_duration}s" "$m1_success/$NUM_REQUESTS"
printf "  %-25s %-15s %-15s\n" "Concurrency Ramp" "$m2_duration" "${ramp_results[$m2_last_n]:-n/a} (at peak)"
printf "  %-25s %-15s %-15s\n" "Single Curl Mode" "${m3_duration}s" "$m3_success/$NUM_REQUESTS"
echo -e "${CYAN}======================================================================${NC}"
