#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi

if [[ -n "${ENDPOINT:-}" ]]; then
  BASE_URL="https://${ENDPOINT}"
else
  HOST="${VON_HOST:-127.0.0.1}"
  PORT="${VON_PORT:-8000}"
  BASE_URL="http://${HOST}:${PORT}"
fi

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

ENDPOINT="/v1/systemone"
STATE="Hi, I was billed twice for March. Please issue a refund today or I will cancel my subscription. The payment gateway keeps throwing timeout errors on my end as well."

print_header() {
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "${BOLD}  SPECULATIVE FAN-OUT TEST${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "Target URL: ${BOLD}$BASE_URL${NC}"
  echo -e ""
  echo -e "Jev (and laya-serve) evaluate all questions in a single forward pass."
  echo -e "Speculative fan-out means sending every question you might need upfront"
  echo -e "— including ones conditional on other answers — and letting code decide"
  echo -e "what is relevant. Extra questions add tokens but not round trips."
  echo
}

print_header

# ----------------------------------------------------------------------
# Test 1: Single question baseline (timing reference)
# ----------------------------------------------------------------------
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${BOLD}[1] SINGLE QUESTION (baseline)${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"

t1_start=$(python3 -c "import time; print(time.perf_counter())")
t1_body=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL$ENDPOINT" \
  ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"von-latest\",
    \"state\": \"$STATE\",
    \"questions\": {
      \"intent\": {
        \"type\": \"choice\",
        \"instructions\": \"What is the primary intent of this message?\",
        \"criteria\": {
          \"refund_request\": \"User explicitly asks for a refund or money back\",
          \"technical_issue\": \"User is reporting a bug, error, or system failure\",
          \"cancellation_threat\": \"User threatens to cancel their account or subscription\",
          \"other\": \"Anything that does not fit the above\"
        }
      }
    }
  }")
t1_end=$(python3 -c "import time; print(time.perf_counter())")
t1_status=$(echo "$t1_body" | tail -n1)
t1_response=$(echo "$t1_body" | head -n -1)
t1_duration=$(python3 -c "print(round($t1_end - $t1_start, 3))")

if [[ "$t1_status" == "200" ]]; then
  echo -e "  Status: ${GREEN}${BOLD}PASS${NC} (HTTP $t1_status) — ${t1_duration}s"
  echo -e "  Questions sent: ${BOLD}1${NC}"
  echo "  Response:"
  echo "$t1_response" | jq '.answers' 2>/dev/null || echo "  $t1_response"
else
  echo -e "  Status: ${RED}${BOLD}FAIL${NC} (HTTP $t1_status)"
  echo "  Body: $t1_response"
fi
echo

# ----------------------------------------------------------------------
# Test 2: Speculative fan-out (all questions in one call)
# ----------------------------------------------------------------------
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${BOLD}[2] SPECULATIVE FAN-OUT (5 questions, one request)${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "  Sending intent + urgency + churn_risk + refund_requested + severity"
echo -e "  in a single call. bug_repro_steps and payment_error are speculative:"
echo -e "  only used if intent routes to the right branch."
echo

t2_start=$(python3 -c "import time; print(time.perf_counter())")
t2_body=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL$ENDPOINT" \
  ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"von-latest\",
    \"state\": \"$STATE\",
    \"questions\": {
      \"intent\": {
        \"type\": \"choice\",
        \"instructions\": \"What is the primary intent of this message?\",
        \"criteria\": {
          \"refund_request\": \"User explicitly asks for a refund or money back\",
          \"technical_issue\": \"User is reporting a bug, error, or system failure\",
          \"cancellation_threat\": \"User threatens to cancel their account or subscription\",
          \"other\": \"Anything that does not fit the above\"
        }
      },
      \"is_urgent\": {
        \"type\": \"noul\",
        \"instructions\": \"Does the message express urgency or require immediate action?\"
      },
      \"churn_risk\": {
        \"type\": \"noul\",
        \"instructions\": \"Does the user threaten to cancel or leave?\"
      },
      \"refund_requested\": {
        \"type\": \"noul\",
        \"instructions\": \"Does the user explicitly request a refund or money back?\"
      },
      \"severity\": {
        \"type\": \"score\",
        \"instructions\": \"Rate the overall severity of this incident.\",
        \"criteria\": [\"Low\", \"Medium\", \"High\", \"Critical\"]
      }
    }
  }")
t2_end=$(python3 -c "import time; print(time.perf_counter())")
t2_status=$(echo "$t2_body" | tail -n1)
t2_response=$(echo "$t2_body" | head -n -1)
t2_duration=$(python3 -c "print(round($t2_end - $t2_start, 3))")

if [[ "$t2_status" == "200" ]]; then
  echo -e "  Status: ${GREEN}${BOLD}PASS${NC} (HTTP $t2_status) — ${t2_duration}s"
  echo -e "  Questions sent: ${BOLD}5${NC}"
  echo "  Response:"
  echo "$t2_response" | jq '.answers' 2>/dev/null || echo "  $t2_response"
else
  echo -e "  Status: ${RED}${BOLD}FAIL${NC} (HTTP $t2_status)"
  echo "  Body: $t2_response"
fi
echo

# ----------------------------------------------------------------------
# Summary: compare latency and show that extra questions cost little time
# ----------------------------------------------------------------------
echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}  SUMMARY${NC}"
echo -e "${CYAN}======================================================================${NC}"
printf "  %-30s %-10s %-10s\n" "Test" "Questions" "Time"
echo -e "  ------------------------------------------------------------------"
printf "  %-30s %-10s %-10s\n" "Single question" "1" "${t1_duration}s"
printf "  %-30s %-10s %-10s\n" "Speculative fan-out" "5" "${t2_duration}s"
echo
echo -e "  Extra questions add tokens but share the same forward pass."
echo -e "  Latency difference should be small; answers should be identical"
echo -e "  for the overlapping question (intent)."
echo -e "${CYAN}======================================================================${NC}"
