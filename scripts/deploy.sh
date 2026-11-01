#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — PBL6-51 production deploy (idempotent; safe to re-run, also used for rollback).
#
# Usage:
#   scripts/deploy.sh [options] compose                 # any host with docker: pull GHCR images, up -d --wait, smoke check
#   scripts/deploy.sh [options] azure up                # Azure VM: az vm start, wait SSH, sync, compose up on VM, smoke via FQDN
#   scripts/deploy.sh [options] azure down              # compose down (optional --compose-down) + az vm deallocate
#   scripts/deploy.sh [options] azure status            # VM power state, FQDN, remote `compose ps`
#   scripts/deploy.sh --tag <sha> azure rollback        # same as `azure up` pinned to a previous image tag (--tag required)
#
# Options:
#   --dry-run            print what would run, change nothing (no az/ssh/pull/up/curl calls)
#   --tag TAG            image tag/sha for all services (IMAGE_TAG). Default: latest
#   --env-file FILE      compose env file (default envs/.env.prod)
#   --compose-down       azure down: also `docker compose down` (never -v) before deallocating
#   --retries N          smoke-check attempts (default 30)
#   --interval SECS      seconds between attempts (default 5)
#   -h, --help
#
# Env (azure target): AZURE_RESOURCE_GROUP, AZURE_VM_NAME, AZURE_VM_SSH_USER (default azureuser), AZURE_SSH_KEY (path to
#   private key), optional AZURE_SUBSCRIPTION_ID, AZURE_VM_HOST (override FQDN/IP), AZURE_REMOTE_DIR (default ~/job-platform),
#   GHCR_USER + GHCR_TOKEN (only if images are private; token goes via ssh stdin, never argv).
# Env (compose target): values from --env-file; smoke URL override COMPOSE_SMOKE_URL (default http://localhost:${GATEWAY_PORT:-5000}/health).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$INFRA_DIR/docker-compose.prod.yml"

DRY_RUN=0
TAG=""
ENV_FILE="$INFRA_DIR/envs/.env.prod"
ACTION=""
COMPOSE_DOWN=0
RETRIES=""
INTERVAL=""
TARGET=""

log() { printf '[deploy] %s\n' "$*"; }
die() { printf '[deploy] ERROR: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '4,26p' "$0" | sed 's/^# \{0,1\}//'; }

# run CMD... : execute, or print when --dry-run
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --tag) [ $# -ge 2 ] || die "--tag needs a value"; TAG="$2"; shift ;;
    --env-file) [ $# -ge 2 ] || die "--env-file needs a value"; ENV_FILE="$2"; shift ;;
    --compose-down) COMPOSE_DOWN=1 ;;
    --retries) [ $# -ge 2 ] || die "--retries needs a value"; RETRIES="$2"; shift ;;
    --interval) [ $# -ge 2 ] || die "--interval needs a value"; INTERVAL="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    compose|azure) [ -z "$TARGET" ] || die "target given twice"; TARGET="$1" ;;
    up|down|status|rollback) [ "$TARGET" = azure ] || die "'$1' only applies to the azure target"; [ -z "$ACTION" ] || die "action given twice"; ACTION="$1" ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { usage >&2; die "missing target: compose|azure"; }
if [ "$TARGET" = azure ]; then
  [ -n "$ACTION" ] || die "azure needs an action: up|down|status|rollback"
  { [ "$ACTION" != rollback ] || [ -n "$TAG" ]; } || die "rollback requires --tag <previous-sha>"
fi
case "$TAG" in *[!A-Za-z0-9._-]*) die "invalid --tag '$TAG'" ;; esac

# smoke URL [retries] [interval] : poll until HTTP 2xx
smoke() {
  local url="$1" retries="$2" interval="$3" i
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] smoke GET %s (up to %s tries, %ss apart)\n' "$url" "$retries" "$interval"
    return 0
  fi
  for ((i = 1; i <= retries; i++)); do
    if curl -fsS -o /dev/null --max-time 10 "$url" 2>/dev/null; then
      log "smoke ok: $url (attempt $i)"
      return 0
    fi
    log "smoke waiting: $url (attempt $i/$retries)"
    sleep "$interval"
  done
  return 1
}

deploy_compose() {
  local retries="${RETRIES:-30}" interval="${INTERVAL:-5}" gw_port smoke_url
  [ "$DRY_RUN" -eq 1 ] || command -v docker >/dev/null 2>&1 || die "docker not found"
  [ "$DRY_RUN" -eq 1 ] || command -v curl >/dev/null 2>&1 || die "curl not found"
  [ "$DRY_RUN" -eq 1 ] || [ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE (see envs/README.md, sync via Infisical prod)"
  [ -n "$TAG" ] && export IMAGE_TAG="$TAG"
  log "compose deploy: file=$COMPOSE_FILE tag=${IMAGE_TAG:-latest}"

  local dc=(docker compose -f "$COMPOSE_FILE")
  [ -f "$ENV_FILE" ] && dc+=(--env-file "$ENV_FILE")

  run "${dc[@]}" config -q
  run "${dc[@]}" pull --ignore-buildable
  run "${dc[@]}" up -d --build --remove-orphans --wait --wait-timeout 300
  run "${dc[@]}" ps

  gw_port="${GATEWAY_PORT:-5000}"
  if [ -f "$ENV_FILE" ] && [ -z "${GATEWAY_PORT:-}" ]; then
    gw_port="$(grep -E '^GATEWAY_PORT=' "$ENV_FILE" | tail -n1 | cut -d= -f2- | tr -d '"' || true)"
    gw_port="${gw_port:-5000}"
  fi
  smoke_url="${COMPOSE_SMOKE_URL:-http://localhost:${gw_port}/health}"
  smoke "$smoke_url" "$retries" "$interval" || die "smoke check failed: $smoke_url — roll back: scripts/deploy.sh --tag <previous-sha> compose"
  log "compose deploy OK"
}

# ── azure target ──────────────────────────────────────────────────────────────
# Config comes from env vars only; the SSH key path is a file, tokens go through stdin.
az_cfg() {
  AZ_RG="${AZURE_RESOURCE_GROUP:-}"; AZ_VM="${AZURE_VM_NAME:-}"
  AZ_USER="${AZURE_VM_SSH_USER:-azureuser}"; AZ_KEY="${AZURE_SSH_KEY:-}"
  AZ_DIR="${AZURE_REMOTE_DIR:-job-platform}"
  local v
  for v in AZURE_RESOURCE_GROUP AZURE_VM_NAME AZURE_SSH_KEY; do
    if [ -z "${!v:-}" ]; then
      [ "$DRY_RUN" -eq 1 ] && log "dry-run: $v is not set (would fail on a real run)" || die "$v is not set"
    fi
  done
  [ "$DRY_RUN" -eq 1 ] || command -v az >/dev/null 2>&1 || die "az CLI not found (https://aka.ms/installazurecli, then az login)"
  [ "$DRY_RUN" -eq 1 ] || command -v ssh >/dev/null 2>&1 || die "ssh not found"
  AZ_RG="${AZ_RG:-<AZURE_RESOURCE_GROUP>}"; AZ_VM="${AZ_VM:-<AZURE_VM_NAME>}"; AZ_KEY="${AZ_KEY:-<AZURE_SSH_KEY>}"
  AZ_SUB=()
  [ -z "${AZURE_SUBSCRIPTION_ID:-}" ] || AZ_SUB=(--subscription "$AZURE_SUBSCRIPTION_ID")
  SSH_OPTS=(-i "$AZ_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)
}

# azc ARGS... : run az (with optional subscription) or print under --dry-run
azc() { run az "$@" "${AZ_SUB[@]}"; }

az_host() {
  if [ -n "${AZURE_VM_HOST:-}" ]; then AZ_HOST="$AZURE_VM_HOST"; return 0; fi
  if [ "$DRY_RUN" -eq 1 ]; then AZ_HOST="<vm-fqdn>"; return 0; fi
  AZ_HOST="$(az vm show -d -g "$AZ_RG" -n "$AZ_VM" "${AZ_SUB[@]}" --query "fqdns || publicIps" -o tsv)"
  [ -n "$AZ_HOST" ] || die "could not resolve VM host (set AZURE_VM_HOST)"
}

az_ssh() { run ssh "${SSH_OPTS[@]}" "$AZ_USER@$AZ_HOST" "$@"; }

az_wait_ssh() {
  local i
  if [ "$DRY_RUN" -eq 1 ]; then printf '[dry-run] wait for ssh %s@%s (up to 40 tries)\n' "$AZ_USER" "$AZ_HOST"; return 0; fi
  for ((i = 1; i <= 40; i++)); do
    if ssh "${SSH_OPTS[@]}" "$AZ_USER@$AZ_HOST" true 2>/dev/null; then log "ssh ready (attempt $i)"; return 0; fi
    log "ssh waiting (attempt $i/40)"; sleep 5
  done
  die "ssh to $AZ_HOST not available"
}

az_sync() {
  local items=("$COMPOSE_FILE" "$INFRA_DIR/docker" "$SCRIPT_DIR/deploy.sh")
  [ "$DRY_RUN" -eq 1 ] || [ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"
  az_ssh "mkdir -p '$AZ_DIR/envs' '$AZ_DIR/scripts'"
  if command -v rsync >/dev/null 2>&1 || [ "$DRY_RUN" -eq 1 ]; then
    local rs=(rsync -az -e "ssh ${SSH_OPTS[*]}")
    run "${rs[@]}" "$COMPOSE_FILE" "$AZ_USER@$AZ_HOST:$AZ_DIR/"
    run "${rs[@]}" --delete "$INFRA_DIR/docker/" "$AZ_USER@$AZ_HOST:$AZ_DIR/docker/"
    run "${rs[@]}" "$SCRIPT_DIR/deploy.sh" "$AZ_USER@$AZ_HOST:$AZ_DIR/scripts/"
    run "${rs[@]}" --chmod=F600 "$ENV_FILE" "$AZ_USER@$AZ_HOST:$AZ_DIR/envs/.env.prod"
  else
    run scp -r "${SSH_OPTS[@]}" "${items[@]}" "$AZ_USER@$AZ_HOST:$AZ_DIR/"
    run scp "${SSH_OPTS[@]}" "$ENV_FILE" "$AZ_USER@$AZ_HOST:$AZ_DIR/envs/.env.prod"
    az_ssh "chmod 600 '$AZ_DIR/envs/.env.prod'"
  fi
}

az_ghcr_login() {
  [ -n "${GHCR_USER:-}" ] && [ -n "${GHCR_TOKEN:-}" ] || return 0
  if [ "$DRY_RUN" -eq 1 ]; then printf '[dry-run] ssh docker login ghcr.io -u <GHCR_USER> --password-stdin (token via stdin)\n'; return 0; fi
  printf '%s' "$GHCR_TOKEN" | ssh "${SSH_OPTS[@]}" "$AZ_USER@$AZ_HOST" "docker login ghcr.io -u '$GHCR_USER' --password-stdin" >/dev/null
}

deploy_azure() {
  az_cfg
  case "$ACTION" in
    up|rollback)
      log "azure $ACTION: vm=$AZ_VM rg=$AZ_RG tag=${TAG:-latest}"
      azc vm start -g "$AZ_RG" -n "$AZ_VM"
      az_host; az_wait_ssh
      az_sync; az_ghcr_login
      local remote=(bash ./scripts/deploy.sh --env-file "envs/.env.prod")
      [ -z "$TAG" ] || remote+=(--tag "$TAG")
      [ -z "$RETRIES" ] || remote+=(--retries "$RETRIES")
      [ -z "$INTERVAL" ] || remote+=(--interval "$INTERVAL")
      az_ssh "cd '$AZ_DIR' && ${remote[*]} compose"
      # external smoke through the public endpoint (needs gateway port open in NSG)
      local gw_port="${GATEWAY_PORT:-5000}"
      if [ -f "$ENV_FILE" ] && [ -z "${GATEWAY_PORT:-}" ]; then
        gw_port="$(grep -E '^GATEWAY_PORT=' "$ENV_FILE" | tail -n1 | cut -d= -f2- | sed 's/[[:space:]]*#.*//' | tr -d '"' || true)"; gw_port="${gw_port:-5000}"
      fi
      smoke "${AZURE_SMOKE_URL:-http://${AZ_HOST}:${gw_port}/health}" "${RETRIES:-30}" "${INTERVAL:-5}" \
        || die "public smoke failed — check NSG/gateway bind; roll back: scripts/deploy.sh --tag <previous-sha> azure rollback"
      log "azure $ACTION OK — remember to run: scripts/deploy.sh azure down"
      ;;
    down)
      if [ "$COMPOSE_DOWN" -eq 1 ]; then
        az_host
        az_ssh "cd '$AZ_DIR' && docker compose -f docker-compose.prod.yml --env-file envs/.env.prod down" || log "compose down skipped (VM unreachable?)"
      fi
      azc vm deallocate -g "$AZ_RG" -n "$AZ_VM"
      log "VM deallocated (only disk cost now)"
      ;;
    status)
      azc vm get-instance-view -g "$AZ_RG" -n "$AZ_VM" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]" -o tsv
      az_host; log "host: $AZ_HOST"
      az_ssh "cd '$AZ_DIR' && docker compose -f docker-compose.prod.yml --env-file envs/.env.prod ps" || log "VM not reachable (deallocated?)"
      ;;
  esac
}

case "$TARGET" in
  compose) deploy_compose ;;
  azure) deploy_azure ;;
esac
