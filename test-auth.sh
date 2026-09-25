#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found" >&2
  exit 1
fi

source "$ENV_FILE"

: "${VON_ROUTE:?VON_ROUTE must be set in .env}"
: "${VON_TOKEN:?VON_TOKEN must be set in .env}"

BASE_URL="https://$VON_ROUTE"
AUTH_PATH="/v1/systemone"
PASS=0
FAIL=0

if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  BLUE=''
  CYAN=''
  BOLD=''
  NC=''
fi

print_header() {
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "${BOLD}  VON-SERVER AUTHENTICATION TESTS${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "Target URL: ${BOLD}$BASE_URL${NC}"
  echo
}

print_section() {
  local num="$1"
  local name="$2"
  echo -e "${BLUE}----------------------------------------------------------------------${NC}"
  echo -e "${BOLD}[$num] $name${NC}"
  echo -e "${BLUE}----------------------------------------------------------------------${NC}"
}

print_test_details() {
  local endpoint="$1"
  local token_desc="$2"
  local expected_desc="$3"
  echo "  Endpoint: $endpoint"
  echo "  Token:    $token_desc"
  echo "  Expected: $expected_desc"
}

check() {
  local expected_pattern="$1"
  local actual="$2"
  local notes="${3:-}"

  if [[ "$actual" =~ ^($expected_pattern)$ ]]; then
    if [[ -n "$notes" ]]; then
      echo -e "  Result:   ${GREEN}${BOLD}PASS${NC} (got $actual, $notes)"
    else
      echo -e "  Result:   ${GREEN}${BOLD}PASS${NC} (got $actual)"
    fi
    PASS=$((PASS + 1))
  else
    echo -e "  Result:   ${RED}${BOLD}FAIL${NC} (expected $expected_pattern, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# Run the test execution
print_header

# 1. Health endpoint bypasses auth
print_section "1" "Health Endpoint (No Token)"
print_test_details "/health" "None (Open endpoint)" "200 OK"
status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
check "200" "$status"
echo

# 2. No token on protected path
print_section "2" "Protected Path - No Token"
print_test_details "$AUTH_PATH" "None" "401 Unauthorized"
status=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" -d '{}' "$BASE_URL$AUTH_PATH")
check "401" "$status"
echo

# 3. Wrong token
print_section "3" "Protected Path - Wrong Token"
print_test_details "$AUTH_PATH" "Invalid/Malformed Token" "401 Unauthorized"
status=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" -H "Authorization: Bearer thisisnotavalidtoken" \
  -d '{}' "$BASE_URL$AUTH_PATH")
check "401" "$status"
echo

# 4. Correct token
print_section "4" "Protected Path - Correct Token"
print_test_details "$AUTH_PATH" "Valid Bearer Token from .env" "200 OK or 422 Unprocessable Entity"
status=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" -H "Authorization: Bearer $VON_TOKEN" \
  -d '{"model":"von-latest","state":"test","questions":{"q":{"type":"noul","instructions":"test?"}}}' \
  "$BASE_URL$AUTH_PATH")
check "200" "$status" "auth accepted"
echo

# Summary
echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}  SUMMARY OF RESULTS${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo "  Total Checked: $((PASS + FAIL))"
echo -e "  Passed:        ${GREEN}$PASS${NC}"
echo -e "  Failed:        ${RED}$FAIL${NC}"
echo

if [[ $FAIL -eq 0 ]]; then
  echo -e "  Status:        ${GREEN}${BOLD}ALL TESTS PASSED ✓${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  exit 0
else
  echo -e "  Status:        ${RED}${BOLD}SOME TESTS FAILED ✗${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  exit 1
fi
