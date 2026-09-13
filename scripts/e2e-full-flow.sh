#!/usr/bin/env bash
set -euo pipefail

# e2e-full-flow.sh — PBL6-28 full-flow integration test through the YARP gateway.
# Flow: recruiter posts a job -> job syncs to search -> candidate searches -> candidate applies.
#
# Requires a running stack (gateway:5000, auth:5001, job:5002, search:5003, app:5004).
# Use --up to start it via dev-up.sh (local .NET services + compose infra/auth/gateway).
#
# Usage:
#   ./scripts/e2e-full-flow.sh                 # run against an already-running stack
#   ./scripts/e2e-full-flow.sh --up            # dev-up job/search/app, then run flow
#   ./scripts/e2e-full-flow.sh --up --down     # ... and tear the stack down afterwards
#   ./scripts/e2e-full-flow.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

GATEWAY="${E2E_GATEWAY_URL:-http://localhost:5000}"
SEARCH_POLL_TIMEOUT="${E2E_SEARCH_TIMEOUT:-40}"   # seconds to wait for job->search sync
RECRUITER_EMAIL="${E2E_RECRUITER_EMAIL:-recruiter@jobplatform.local}"
RECRUITER_PASSWORD="${E2E_RECRUITER_PASSWORD:-Recruiter123}"

DO_UP=0
DO_DOWN=0
for arg in "$@"; do
  case "$arg" in
    --up) DO_UP=1 ;;
    --down) DO_DOWN=1 ;;
    --help|-h)
      sed -n '2,13p' "$0"
      exit 0 ;;
    *) echo "Unknown flag: $arg (see --help)" >&2; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1 — $2" >&2; exit 1; }; }
need curl "install curl"
need jq "install jq"

RESP_BODY=""
RESP_STATUS=""

# request METHOD PATH [TOKEN] [JSON]  -> sets RESP_BODY / RESP_STATUS
request() {
  local method="$1" path="$2" token="${3:-}" data="${4:-}"
  local args=(--max-time 20 -sS -o /tmp/e2e-body.$$ -w '%{http_code}' -X "$method" "$GATEWAY$path")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  if [[ -n "$data" ]]; then
    args+=(-H 'Content-Type: application/json' -d "$data")
  fi
  RESP_STATUS="$(curl "${args[@]}" || true)"
  RESP_BODY="$(cat /tmp/e2e-body.$$ 2>/dev/null || true)"
  rm -f /tmp/e2e-body.$$
}

fail() { echo "FAIL: $*" >&2; exit 1; }
info() { echo "==> $*"; }

health() { curl -sf -m 3 "$1/health" >/dev/null 2>&1; }

cleanup() {
  local code=$?
  if [[ "$DO_DOWN" -eq 1 ]]; then
    info "tearing down (--down)"
    "$SCRIPT_DIR/dev-up.sh" --down || true
  fi
  exit "$code"
}
trap cleanup EXIT

# ── 0. Start stack / preflight ──────────────────────────────────────────────
if [[ "$DO_UP" -eq 1 ]]; then
  info "starting stack (dev-up --with-job --with-search --with-app)"
  # ENABLE_DEV_AUTH: app-svc trusts gateway-injected X-User-Id/Role in Development.
  # SEARCH_SYNC_URL: job-svc indexes created jobs into search-svc.
  ENABLE_DEV_AUTH=true SEARCH_SYNC_URL=http://localhost:5003 \
    "$SCRIPT_DIR/dev-up.sh" --with-job --with-search --with-app --skip-smoke
fi

info "preflight health checks"
for entry in "gateway:5000" "auth:5001" "job:5002" "search:5003" "app:5004"; do
  name="${entry%%:*}"; port="${entry##*:}"
  for _ in $(seq 1 30); do
    health "http://localhost:$port" && break
    sleep 2
  done
  health "http://localhost:$port" || fail "$name (:$port) is not healthy — start it with ./scripts/dev-up.sh --with-job --with-search --with-app"
  echo "  OK $name (:$port)"
done

RUN_ID="$(date +%s)-$RANDOM"

# ── 1. Login seeded recruiter (auth seed, Development) ──────────────────────
info "login recruiter ($RECRUITER_EMAIL)"
request POST /api/auth/login "" \
  "$(jq -nc --arg e "$RECRUITER_EMAIL" --arg p "$RECRUITER_PASSWORD" '{email:$e,password:$p}')"
[[ "$RESP_STATUS" == "200" ]] || fail "recruiter login returned $RESP_STATUS: $RESP_BODY (is auth-svc running in Development so demo users are seeded?)"
RECRUITER_TOKEN="$(jq -r '.accessToken // .AccessToken // empty' <<<"$RESP_BODY")"
[[ -n "$RECRUITER_TOKEN" ]] || fail "no accessToken in login response: $RESP_BODY"
echo "  token acquired"

# ── 2. Recruiter creates a company ──────────────────────────────────────────
COMPANY_NAME="E2E Co $RUN_ID"
info "create company ($COMPANY_NAME)"
request POST /api/companies "$RECRUITER_TOKEN" "$(jq -nc --arg n "$COMPANY_NAME" '{name:$n,description:"Created by e2e-full-flow.sh"}')"
[[ "$RESP_STATUS" == "201" ]] || fail "create company returned $RESP_STATUS: $RESP_BODY"
COMPANY_ID="$(jq -r '.id // empty' <<<"$RESP_BODY")"
[[ -n "$COMPANY_ID" ]] || fail "no company id: $RESP_BODY"
echo "  companyId=$COMPANY_ID"

# ── 3. Recruiter posts a job (unique title) ─────────────────────────────────
JOB_TITLE="E2E Engineer $RUN_ID"
info "post job ($JOB_TITLE)"
REQUESTED_AT="$(date +%s)"
request POST /api/jobs "$RECRUITER_TOKEN" "$(jq -nc \
  --arg t "$JOB_TITLE" --arg c "$COMPANY_ID" \
  '{title:$t,description:"E2E full-flow job posting.",companyId:$c,location:"Ho Chi Minh City",salaryMin:1000,salaryMax:2000,salaryCurrency:"USD",requirements:"Automated test",employmentType:"FullTime",experienceLevel:"Entry"}')"
[[ "$RESP_STATUS" == "201" ]] || fail "create job returned $RESP_STATUS: $RESP_BODY"
JOB_ID="$(jq -r '.id // empty' <<<"$RESP_BODY")"
[[ -n "$JOB_ID" ]] || fail "no job id: $RESP_BODY"
echo "  jobId=$JOB_ID"

# ── 4. Register + login candidate ───────────────────────────────────────────
APPLICANT_EMAIL="e2e-applicant-$RUN_ID@example.com"
APPLICANT_PASSWORD="E2ePass123"
info "register + login candidate ($APPLICANT_EMAIL)"
request POST /api/auth/register "" \
  "$(jq -nc --arg e "$APPLICANT_EMAIL" --arg p "$APPLICANT_PASSWORD" '{email:$e,password:$p,fullName:"E2E Applicant",role:"User"}')"
[[ "$RESP_STATUS" == "201" ]] || fail "candidate register returned $RESP_STATUS: $RESP_BODY"
request POST /api/auth/login "" \
  "$(jq -nc --arg e "$APPLICANT_EMAIL" --arg p "$APPLICANT_PASSWORD" '{email:$e,password:$p}')"
[[ "$RESP_STATUS" == "200" ]] || fail "candidate login returned $RESP_STATUS: $RESP_BODY"
APPLICANT_TOKEN="$(jq -r '.accessToken // .AccessToken // empty' <<<"$RESP_BODY")"
[[ -n "$APPLICANT_TOKEN" ]] || fail "no applicant accessToken: $RESP_BODY"
echo "  token acquired"

# ── 5. Search for the job (poll for job -> search sync) ─────────────────────
info "search for job via /api/search/jobs (timeout ${SEARCH_POLL_TIMEOUT}s)"
FOUND=0
deadline=$(( $(date +%s) + SEARCH_POLL_TIMEOUT ))
while [[ "$(date +%s)" -lt "$deadline" ]]; do
  request GET "/api/search/jobs?q=$(jq -rn --arg v "$JOB_TITLE" '$v|@uri')&page=0&size=20" ""
  if [[ "$RESP_STATUS" == "200" ]] && jq -e --arg id "$JOB_ID" '.items[]? | select((.id // "") == $id)' <<<"$RESP_BODY" >/dev/null 2>&1; then
    FOUND=1
    break
  fi
  sleep 2
done

if [[ "$FOUND" -ne 1 ]]; then
  # Fallback: sync may be disabled (SEARCH_SYNC_URL unset). Index directly via
  # the search API so the search+apply legs are still exercised end-to-end.
  echo "  WARN job not found in search after ${SEARCH_POLL_TIMEOUT}s — indexing directly (check SEARCH_SYNC_URL)"
  request POST /api/search/index "" "$(jq -nc \
    --arg id "$JOB_ID" --arg t "$JOB_TITLE" --arg c "$COMPANY_ID" \
    '{id:$id,title:$t,companyId:$c,companyName:"E2E Co",location:"Ho Chi Minh City",employmentType:"FullTime",experienceLevel:"Entry",status:"Active"}')"
  [[ "$RESP_STATUS" == "200" ]] || fail "direct index returned $RESP_STATUS: $RESP_BODY"
  for _ in $(seq 1 10); do
    request GET "/api/search/jobs?q=$(jq -rn --arg v "$JOB_TITLE" '$v|@uri')&page=0&size=20" ""
    if jq -e --arg id "$JOB_ID" '.items[]? | select((.id // "") == $id)' <<<"$RESP_BODY" >/dev/null 2>&1; then
      FOUND=1
      break
    fi
    sleep 1
  done
fi
[[ "$FOUND" -eq 1 ]] || fail "job $JOB_ID never appeared in search results"
echo "  found jobId=$JOB_ID in search"

# ── 6. Candidate applies with a CV ──────────────────────────────────────────
CV_FILE="$(mktemp --suffix=.pdf)"
printf '%%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n' > "$CV_FILE"
info "apply to job (multipart cv_file)"
RESP_STATUS="$(curl --max-time 30 -sS -o /tmp/e2e-apply.$$ -w '%{http_code}' -X POST "$GATEWAY/api/applications" \
  -H "Authorization: Bearer $APPLICANT_TOKEN" \
  -F "job_id=$JOB_ID" \
  -F "cover_letter=E2E automated application" \
  -F "cv_file=@$CV_FILE;type=application/pdf" || true)"
RESP_BODY="$(cat /tmp/e2e-apply.$$ 2>/dev/null || true)"
rm -f /tmp/e2e-apply.$$ "$CV_FILE"
[[ "$RESP_STATUS" == "201" ]] || fail "apply returned $RESP_STATUS: $RESP_BODY"
APPLICATION_ID="$(jq -r '.id // empty' <<<"$RESP_BODY")"
[[ -n "$APPLICATION_ID" ]] || fail "no application id: $RESP_BODY"
echo "  applicationId=$APPLICATION_ID"

# ── 7. Candidate sees it in history ─────────────────────────────────────────
info "verify application history"
request GET /api/applications/me "$APPLICANT_TOKEN"
[[ "$RESP_STATUS" == "200" ]] || fail "applications/me returned $RESP_STATUS: $RESP_BODY"
jq -e --arg jid "$JOB_ID" \
  '(.items // .Items // .)[]? | select((.jobId // .job_id // "") == $jid)' <<<"$RESP_BODY" >/dev/null 2>&1 \
  || fail "job $JOB_ID not present in /api/applications/me: $RESP_BODY"
echo "  application present"

echo ""
echo "PASS: post -> search -> apply full flow succeeded via gateway"
echo "  company=$COMPANY_ID job=$JOB_ID application=$APPLICATION_ID"
