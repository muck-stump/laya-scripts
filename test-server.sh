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
  HOST="${LAYA_HOST:-127.0.0.1}"
  PORT="${LAYA_PORT:-8000}"
  BASE_URL="http://${HOST}:${PORT}"
fi

AUTH_HEADER=()
if [[ -n "${API_KEY:-}" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${API_KEY}")
fi

echo "========================================="
echo "Testing Laya Server at: ${BASE_URL}"
echo "========================================="

echo ""
echo "--> 1. Health Check (GET /health)"
curl -s -f "${BASE_URL}/health" | jq || { echo "Health check failed!"; exit 1; }

echo ""
echo "--> 2. System One Inference (POST /v1/systemone)"
curl -s -f -X POST "${BASE_URL}/v1/systemone" \
  ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
  -H "Content-Type: application/json" \
  -d '{
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
  }' | jq || { echo "Inference failed!"; exit 1; }

echo ""
echo "========================================="
echo "All tests passed successfully!"
echo "========================================="
