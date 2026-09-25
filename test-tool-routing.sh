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

# The user query being evaluated against all tools.
USER_QUERY="My payment keeps failing at checkout and I've been trying for two days. I need to fix this urgently or I'll have to cancel my order."

echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}  TOOL ROUTING TEST (speculative fan-out)${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo -e "Target URL: ${BOLD}$BASE_URL${NC}"
echo -e "Endpoint:   ${BOLD}$ENDPOINT${NC}"
echo
echo -e "User query:"
echo -e "  ${YELLOW}\"$USER_QUERY\"${NC}"
echo
echo -e "One request. One forward pass. A noul per tool: is this tool"
echo -e "appropriate for the query? Code reads the probabilities and"
echo -e "reports which tools are above threshold."
echo -e "${CYAN}======================================================================${NC}"
echo

THRESHOLD="0.5"

response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL$ENDPOINT" \
  ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"von-latest\",
    \"state\": \"$USER_QUERY\",
    \"questions\": {
      \"tool_refund_lookup\": {
        \"type\": \"noul\",
        \"instructions\": \"Is a refund lookup or refund status tool appropriate for this query?\"
      },
      \"tool_payment_retry\": {
        \"type\": \"noul\",
        \"instructions\": \"Is a payment retry or reprocess payment tool appropriate for this query?\"
      },
      \"tool_order_status\": {
        \"type\": \"noul\",
        \"instructions\": \"Is an order status or order tracking tool appropriate for this query?\"
      },
      \"tool_account_lookup\": {
        \"type\": \"noul\",
        \"instructions\": \"Is a user account lookup tool appropriate for this query?\"
      },
      \"tool_escalate_human\": {
        \"type\": \"noul\",
        \"instructions\": \"Should this query be escalated to a human agent?\"
      },
      \"tool_send_email\": {
        \"type\": \"noul\",
        \"instructions\": \"Is a send confirmation or notification email tool appropriate for this query?\"
      },
      \"tool_knowledge_base\": {
        \"type\": \"noul\",
        \"instructions\": \"Is a knowledge base or FAQ search tool appropriate for this query?\"
      },
      \"tool_cancel_order\": {
        \"type\": \"noul\",
        \"instructions\": \"Is an order cancellation tool appropriate for this query?\"
      },
      \"tool_fraud_check\": {
        \"type\": \"noul\",
        \"instructions\": \"Is a fraud detection or transaction review tool appropriate for this query?\"
      },
      \"tool_create_ticket\": {
        \"type\": \"noul\",
        \"instructions\": \"Is creating a support ticket the right action for this query?\"
      }
    }
  }")

status=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n -1)

echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${BOLD}  RAW SCORES (noul = P(appropriate))${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"

if [[ "$status" != "200" ]]; then
  echo -e "${RED}${BOLD}FAIL${NC} — HTTP $status"
  echo "$body"
  exit 1
fi

echo "$body" | jq -r '
  .answers | to_entries[] |
  "\(.key) \(.value.noul)"
' | sort -k2 -rn | while read -r tool score; do
  padded=$(printf "%-30s" "$tool")
  bar_len=$(python3 -c "print(int(float('$score') * 40))")
  bar=$(python3 -c "print('█' * $bar_len)")
  printf "  %s  %.3f  %s\n" "$padded" "$score" "$bar"
done

echo
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${BOLD}  TOOLS ABOVE THRESHOLD (noul >= $THRESHOLD)${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"

matched=$(echo "$body" | jq -r --argjson t "$THRESHOLD" '
  .answers | to_entries[]
  | select(.value.noul >= $t)
  | "\(.key) \(.value.noul)"
' | sort -k2 -rn)

if [[ -z "$matched" ]]; then
  echo -e "  ${YELLOW}No tools above threshold $THRESHOLD${NC}"
else
  echo "$matched" | while read -r tool score; do
    echo -e "  ${GREEN}${BOLD}✓${NC} $tool  (${score})"
  done
fi

echo
echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}  DONE${NC}"
echo -e "${CYAN}======================================================================${NC}"
