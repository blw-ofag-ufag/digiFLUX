#!/bin/bash
# simulation of shipment creation, acceptance and checking using the digiFLUX shipments API
# The script does he following:
# 1) authenticate with tech user 1 as sender
# 2) authenticate with tech user 1 as recipient
# 3) submit shipment as sender using POST
# 4) wait 120 secs (until shipment has automatically changed from state CREATED to SENT
#    (and can thus be accepted by recipient
# 5) accept delivery as recipient using PUT
# 6) check state of delivery as sender using GET
#
# version 1.0 Andreas Kyriacou 2025-11-13
#

set -euo pipefail

# 🎨 Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# 🌈 Default flags
DRY_RUN=false
VERBOSE=false

# 🧭 Parse command-line options
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --verbose) VERBOSE=true ;;
    --help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --dry-run      Skip all curl calls (mock responses)"
      echo "  --verbose      Print full API responses"
      echo "  --help         Show this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}[ERROR] Unknown option: $arg${NC}"
      echo "Use --help to see valid options."
      exit 1
      ;;
  esac
done

# 🧾 Logging function
log() {
  local level="$1"; shift
  case "$level" in
    INFO) echo -e "${BLUE}[INFO]${NC} $*" ;;
    SUCCESS) echo -e "${GREEN}[OK]${NC} $*" ;;
    WARN) echo -e "${YELLOW}[WARN]${NC} $*" ;;
    ERROR) echo -e "${RED}[ERROR]${NC} $*" ;;
    *) echo "[LOG] $*" ;;
  esac
}

divider() { echo -e "${BLUE}----------------------------------------${NC}"; }

# 🧪 Dry-run wrapper
maybe_curl() {
  if [ "$DRY_RUN" = true ]; then
    log WARN "Dry-run enabled: skipping curl."
    echo "{}"
  else
    curl "$@"
  fi
}

# 🔧 Parsers
extract_field() {
  local key="$1"
  sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p"
}

extract_nested_field() {
  local parent="$1"
  local child="$2"
  sed -n "s/.*\"$parent\":{.*\"$child\":\"\([^\"]*\)\".*}.*/\1/p"
}

parse_status_response() {
  local response="$1"
  PUT_BODY=$(sed -n '1,/HTTP_STATUS:/p' <<< "$response" | sed '$d')
  PUT_STATUS=$(grep HTTP_STATUS <<< "$response" | cut -d':' -f2)
}

# 🌐 URLs
TOKEN_URL="https://idp-rf.agate.ch/auth/realms/agate/protocol/openid-connect/token"
API_URL="https://rf-vp.agate.ch/digiflux/core/transactions/b2b/shipments"

# 🎯 Credentials
# replace with your values
CLIENT_ID_1="999999"
CLIENT_SECRET_1="xxxxxxxxxx"
CLIENT_ID_2="999999"
CLIENT_SECRET_2="xxxxxxxxxx"

# 🔐 Get access tokens
log INFO "Fetching sender token..."
TOKEN_RESPONSE_1=$(maybe_curl -sk -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID_1" \
  -d "client_secret=$CLIENT_SECRET_1")
[ "$VERBOSE" = true ] && log INFO "Response:\n$TOKEN_RESPONSE_1"
ACCESS_TOKEN_1=$(extract_field "access_token" <<< "$TOKEN_RESPONSE_1")

log INFO "Fetching recipient token..."
TOKEN_RESPONSE_2=$(maybe_curl -sk -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID_2" \
  -d "client_secret=$CLIENT_SECRET_2")
[ "$VERBOSE" = true ] && log INFO "Response:\n$TOKEN_RESPONSE_2"
ACCESS_TOKEN_2=$(extract_field "access_token" <<< "$TOKEN_RESPONSE_2")

# 📦 Prepare delivery
timestamp=$(date +"%Y-%m-%d %H:%M:%S")
PAYLOAD=$(cat <<EOF
{
  "comment": "delivery notification submitted via API at $timestamp",
  "shipmentDate": "$timestamp",
  "productFamily": "TRADE_PRODUCT",
  "product": {
    "id": "7610176071600",
    "sourceSystemId": "GTIN"
  },
  "quantity": {
    "value": 2,
    "unit": "pc"
  },
  "shippedFromStock": {
    "id": "A14465139",
    "sourceSystemId": "BUR"
  },
  "shippedToStock": {
    "id": "D02384766",
    "sourceSystemId": "DFLID"
  }
}
EOF
)

divider
log INFO "Sending delivery POST..."
POST_RESPONSE=$(maybe_curl -sk -w "\nHTTP_STATUS:%{http_code}" -X POST "$API_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN_1" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")
[ "$VERBOSE" = true ] && log INFO "Response:\n$POST_RESPONSE"

BODY=$(sed -n '1,/HTTP_STATUS:/p' <<< "$POST_RESPONSE" | sed '$d')
STATUS=$(grep HTTP_STATUS <<< "$POST_RESPONSE" | cut -d':' -f2)

if [ "$STATUS" = "200" ]; then
  log SUCCESS "Delivery created."
else
  log ERROR "POST failed (HTTP $STATUS)"
  echo "$BODY"
  exit 1
fi

# 🆔 Extract IDs
ID=$(extract_field "id" <<< "$BODY")
SOURCE_SYSTEM_ID=$(extract_field "sourceSystemId" <<< "$BODY")
GET_URL="$API_URL/$SOURCE_SYSTEM_ID/$ID"



divider
log INFO "Checking delivery state..."
GET_RESPONSE=$(maybe_curl -sk -X GET "$GET_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN_1" \
  -H "Content-Type: application/json")
[ "$VERBOSE" = true ] && log INFO "Response:\n$GET_RESPONSE"

STATUS_VALUE=$(extract_nested_field "productShipmentStatus" "id" <<< "$GET_RESPONSE")
log INFO "Initial state: $STATUS_VALUE"

divider
log INFO "Waiting 120s for background update..."
sleep 120

GET_RESPONSE=$(maybe_curl -sk -X GET "$GET_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN_1" \
  -H "Content-Type: application/json")
[ "$VERBOSE" = true ] && log INFO "Response:\n$GET_RESPONSE"

STATUS_VALUE=$(extract_nested_field "productShipmentStatus" "id" <<< "$GET_RESPONSE")
log INFO "Updated status: $STATUS_VALUE"

# 📨 Accept delivery
PUT_URL="$API_URL/$SOURCE_SYSTEM_ID/$ID/status"
PUT_PAYLOAD='{"newStatus":"ACCEPTED"}'

divider
log INFO "Sending PUT to accept delivery..."
PUT_RESPONSE=$(maybe_curl -sk -w "\nHTTP_STATUS:%{http_code}" -X PUT "$PUT_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN_2" \
  -H "Content-Type: application/json" \
  -d "$PUT_PAYLOAD")
[ "$VERBOSE" = true ] && log INFO "Response:\n$PUT_RESPONSE"

parse_status_response "$PUT_RESPONSE"

#check

if [ "$PUT_STATUS" = "204" ]; then
  log SUCCESS "Delivery accepted by recipient."
else
  log ERROR "PUT failed (HTTP $PUT_STATUS)"
  echo "$PUT_BODY"
fi

# 🔁 Final confirmation
divider
log INFO "Confirming final delivery status..."
GET_RESPONSE_Lf=$(maybe_curl -sk -X GET "$GET_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN_1" \
  -H "Content-Type: application/json")

# EXTRACTED_ID=$(extract_field "id" <<< "$GET_RESPONSE_Lf" | head -n 1)
# EXTRACTED_SOURCE_SYSTEM_ID=$(extract_field "sourceSystemId" <<< "$GET_RESPONSE_Lf" | head -n 1)
# STATUS_VALUE=$(extract_nested_field "productShipmentStatus" "id" <<< "$GET_RESPONSE_Lf" | head -n 1)

EXTRACTED_ID="$ID"
EXTRACTED_SOURCE_SYSTEM_ID="$SOURCE_SYSTEM_ID"


STATUS_VALUE=$(echo "$GET_RESPONSE_Lf" | sed -n 's/.*"productShipmentStatus":{"id":"\([^"]*\)".*/\1/p')

#test

log INFO "Final delivery state: $STATUS_VALUE"

if [ "$STATUS_VALUE" = "ACCEPTED" ]; then
  log SUCCESS "Delivery successfully marked as ACCEPTED."
else
  log WARN "Delivery not yet accepted."
fi
