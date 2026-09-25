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

# The user query being evaluated against all skills.
USER_QUERY="List the moons of jupiter"

echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}  SKILL ROUTING TEST (speculative fan-out)${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo -e "Target URL: ${BOLD}$BASE_URL${NC}"
echo -e "Endpoint:   ${BOLD}$ENDPOINT${NC}"
echo
echo -e "User query:"
echo -e "  ${YELLOW}\"$USER_QUERY\"${NC}"
echo
echo -e "One request. One forward pass. A noul per skill: should this skill"
echo -e "be activated for the query? The LLM scores each skill independently"
echo -e "and reports which are above threshold."
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
      \"skill_internet_use\": {
        \"type\": \"noul\",
        \"instructions\": \"Should the internet-use skill be activated? It enables the LLM to browse the web and fetch live information.\"
      },
      \"skill_astronomy\": {
        \"type\": \"noul\",
        \"instructions\": \"Should an astronomy or space-science skill be activated? It provides deep knowledge of planets, moons, stars, and the solar system.\"
      },
      \"skill_code_interpreter\": {
        \"type\": \"noul\",
        \"instructions\": \"Should a code interpreter or data analysis skill be activated? It lets the LLM write and execute code.\"
      },
      \"skill_image_generation\": {
        \"type\": \"noul\",
        \"instructions\": \"Should an image generation skill be activated? It lets the LLM produce visual artwork or diagrams.\"
      },
      \"skill_document_summariser\": {
        \"type\": \"noul\",
        \"instructions\": \"Should a document summarisation skill be activated? It extracts key points from long texts or uploaded files.\"
      },
      \"skill_translation\": {
        \"type\": \"noul\",
        \"instructions\": \"Should a language translation skill be activated? It converts text between human languages.\"
      },
      \"skill_calendar_scheduling\": {
        \"type\": \"noul\",
        \"instructions\": \"Should a calendar or scheduling skill be activated? It manages events, reminders, and time-based planning.\"
      },
      \"skill_finance_analysis\": {
        \"type\": \"noul\",
        \"instructions\": \"Should a finance or stock-market analysis skill be activated? It interprets financial data and market trends.\"
      },
      \"skill_recipe_generator\": {
        \"type\": \"noul\",
        \"instructions\": \"Should a recipe generation skill be activated? It suggests meal ideas and cooking instructions.\"
      },
      \"skill_math_solver\": {
        \"type\": \"noul\",
        \"instructions\": \"Should a mathematics or equation-solving skill be activated? It handles symbolic maths, proofs, and numerical computation.\"
      }
    }
  }")

status=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n -1)

echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${BOLD}  RAW SCORES (noul = P(skill relevant))${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"

if [[ "$status" != "200" ]]; then
  echo -e "${RED}${BOLD}FAIL${NC} — HTTP $status"
  echo "$body"
  exit 1
fi

echo "$body" | jq -r '
  .answers | to_entries[] |
  "\(.key) \(.value.noul)"
' | sort -k2 -rn | while read -r skill score; do
  padded=$(printf "%-30s" "$skill")
  bar_len=$(python3 -c "print(int(float('$score') * 40))")
  bar=$(python3 -c "print('█' * $bar_len)")
  printf "  %s  %.3f  %s\n" "$padded" "$score" "$bar"
done

echo
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${BOLD}  SKILLS ABOVE THRESHOLD (noul >= $THRESHOLD)${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"

matched=$(echo "$body" | jq -r --argjson t "$THRESHOLD" '
  .answers | to_entries[]
  | select(.value.noul >= $t)
  | "\(.key) \(.value.noul)"
' | sort -k2 -rn)

if [[ -z "$matched" ]]; then
  echo -e "  ${YELLOW}No skills above threshold $THRESHOLD${NC}"
else
  echo "$matched" | while read -r skill score; do
    echo -e "  ${GREEN}${BOLD}✓${NC} $skill  (${score})"
  done
fi

echo
echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}  DONE${NC}"
echo -e "${CYAN}======================================================================${NC}"
