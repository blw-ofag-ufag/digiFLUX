#!/bin/bash
# example of using the LocalUnits query to obtain the DFLID of a stock
# search params are added to the URL - see API_URL. Example used: ?name=BLW
#
# version 1.0 Andreas Kyriacou 2025-12-04
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


# 🌐 URLs
TOKEN_URL="https://idp-rf.agate.ch/auth/realms/agate/protocol/openid-connect/token"
API_URL="https://wsg-vp.isceco.admin.ch/agriculture/digiflux/stocks/1/b2b/localUnits/?name=BLW"

# 🎯 Credentials
CLIENT_ID="999999"
CLIENT_SECRET="xxxxx"

# 🔐 Get access tokens
log INFO "Fetching sender token..."
TOKEN_RESPONSE=$(maybe_curl -sk -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET")
[ "$VERBOSE" = true ] && log INFO "Response:\n$TOKEN_RESPONSE"
ACCESS_TOKEN=$(extract_field "access_token" <<< "$TOKEN_RESPONSE")

divider
log INFO "get local units..."
GET_RESPONSE=$(maybe_curl -sk -X GET "$API_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

echo "$GET_RESPONSE"
