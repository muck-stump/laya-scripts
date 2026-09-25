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

# The user query being evaluated against all skills (Indonesian).
USER_QUERY="Daftarkan bulan-bulan planet Jupiter. Saya ingin penjelasan yang spesifik dan lengkap — nama, ukuran, karakteristik orbit, dan fitur-fitur penting dari masing-masing bulan. Akurasi sangat penting karena bulan-bulan baru masih terus ditemukan dan jumlahnya berubah dari waktu ke waktu. Pastikan informasi yang diberikan seakurat mungkin dan tidak bergantung pada data pelatihan yang mungkin sudah usang. Jika Anda tidak yakin suatu informasi masih mutakhir, harap sampaikan."

echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}  SKILL ROUTING TEST — INDONESIAN (speculative fan-out)${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo -e "Target URL: ${BOLD}$BASE_URL${NC}"
echo -e "Endpoint:   ${BOLD}$ENDPOINT${NC}"
echo
echo -e "User query (id):"
echo -e "  ${YELLOW}\"$USER_QUERY\"${NC}"
echo
echo -e "One request. One forward pass. A noul per skill: should this skill"
echo -e "be activated for the query? The LLM scores each skill independently"
echo -e "and reports which are above threshold."
echo -e "${CYAN}======================================================================${NC}"
echo

THRESHOLD="0.5"

# Write payload via python to safely handle non-ASCII characters (em dashes etc.)
PAYLOAD_FILE=$(mktemp /tmp/laya-request-XXXXXX.json)
python3 -c "
import json, sys
state = sys.argv[1]
payload = {
  'model': 'multilingual',
  'state': state,
  'questions': {
    'skill_internet_use':       {'type': 'noul', 'instructions': 'Apakah skill penggunaan internet perlu diaktifkan? Skill ini memungkinkan LLM menjelajahi web, mengambil informasi terkini, dan mengumpulkan sumber yang akurat dan up-to-date.'},
    'skill_astronomy':          {'type': 'noul', 'instructions': 'Apakah skill astronomi atau ilmu antariksa perlu diaktifkan? Skill ini memberikan pengetahuan mendalam tentang planet, bulan, bintang, dan tata surya.'},
    'skill_code_interpreter':   {'type': 'noul', 'instructions': 'Apakah skill interpreter kode atau analisis data perlu diaktifkan? Skill ini memungkinkan LLM menulis dan mengeksekusi kode.'},
    'skill_image_generation':   {'type': 'noul', 'instructions': 'Apakah skill pembuatan gambar perlu diaktifkan? Skill ini memungkinkan LLM menghasilkan karya seni visual atau diagram.'},
    'skill_document_summariser':{'type': 'noul', 'instructions': 'Apakah skill ringkasan dokumen perlu diaktifkan? Skill ini mengekstrak poin-poin penting dari teks panjang atau file yang diunggah.'},
    'skill_translation':        {'type': 'noul', 'instructions': 'Apakah skill terjemahan bahasa perlu diaktifkan? Skill ini mengonversi teks antar bahasa manusia.'},
    'skill_calendar_scheduling':{'type': 'noul', 'instructions': 'Apakah skill kalender atau penjadwalan perlu diaktifkan? Skill ini mengelola acara, pengingat, dan perencanaan berbasis waktu.'},
    'skill_finance_analysis':   {'type': 'noul', 'instructions': 'Apakah skill analisis keuangan atau pasar saham perlu diaktifkan? Skill ini menginterpretasikan data keuangan dan tren pasar.'},
    'skill_recipe_generator':   {'type': 'noul', 'instructions': 'Apakah skill pembuatan resep perlu diaktifkan? Skill ini menyarankan ide masakan dan instruksi memasak.'},
    'skill_math_solver':        {'type': 'noul', 'instructions': 'Apakah skill matematika atau pemecahan persamaan perlu diaktifkan? Skill ini menangani matematika simbolik, pembuktian, dan komputasi numerik.'},
  }
}
print(json.dumps(payload, ensure_ascii=False))
" "$USER_QUERY" > "$PAYLOAD_FILE"

response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL$ENDPOINT" \
  ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
  -H "Content-Type: application/json" \
  -d "@$PAYLOAD_FILE")

rm -f "$PAYLOAD_FILE"

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
