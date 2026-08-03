#!/usr/bin/env bash
# Create or update the protect-main repository ruleset from .github/rulesets/main.json
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-AveryLor/oscilloscope-dev}"
TOKEN="${RULESET_TOKEN:-${GITHUB_TOKEN:-}}"
API_VERSION="2022-11-28"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULESET_FILE="${SCRIPT_DIR}/../rulesets/main.json"

if [[ -z "${TOKEN}" ]]; then
  echo "error: set RULESET_TOKEN (or GITHUB_TOKEN) with Administration read/write on ${REPO}" >&2
  exit 1
fi

if [[ ! -f "${RULESET_FILE}" ]]; then
  echo "error: ruleset file not found: ${RULESET_FILE}" >&2
  exit 1
fi

RULESET_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "${RULESET_FILE}")"

api() {
  local method="$1"
  local path="$2"
  shift 2
  curl -sS \
    -X "${method}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${API_VERSION}" \
    "$@" \
    "https://api.github.com${path}"
}

echo "Looking up existing rulesets on ${REPO}..."
LIST_JSON="$(api GET "/repos/${REPO}/rulesets")"

EXISTING_ID="$(
  export RULESET_NAME
  python3 -c '
import json, os, sys
data = json.load(sys.stdin)
name = os.environ["RULESET_NAME"]
if isinstance(data, dict) and data.get("message"):
    print("error: " + str(data.get("message")), file=sys.stderr)
    sys.exit(1)
for item in data:
    if item.get("name") == name:
        print(item["id"])
        break
' <<<"${LIST_JSON}"
)"

if [[ -n "${EXISTING_ID}" ]]; then
  echo "Updating ruleset '${RULESET_NAME}' (id=${EXISTING_ID})..."
  RESP="$(api PUT "/repos/${REPO}/rulesets/${EXISTING_ID}" \
    -H "Content-Type: application/json" \
    --data @"${RULESET_FILE}")"
else
  echo "Creating ruleset '${RULESET_NAME}'..."
  RESP="$(api POST "/repos/${REPO}/rulesets" \
    -H "Content-Type: application/json" \
    --data @"${RULESET_FILE}")"
fi

python3 -c '
import json, sys
data = json.load(sys.stdin)
if "message" in data and "id" not in data:
    print("error: " + str(data.get("message")), file=sys.stderr)
    if data.get("errors"):
        print(json.dumps(data["errors"], indent=2), file=sys.stderr)
    sys.exit(1)
print(
    "OK: ruleset id=%s name=%s enforcement=%s"
    % (data.get("id"), data.get("name"), data.get("enforcement"))
)
' <<<"${RESP}"
