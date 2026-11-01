#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — PBL6-51 production deploy (idempotent; safe to re-run, also used for rollback).
#
# Usage:
#   scripts/deploy.sh [options] compose            # single host: pull GHCR images, up -d, smoke check
#   scripts/deploy.sh [options] render             # Render: trigger deploy hooks, smoke check
#
# Options:
#   --dry-run            print what would run, change nothing (no pull/up/curl/hook calls)
#   --tag TAG            image tag/sha for all services (compose: IMAGE_TAG; render: hook ref=TAG). Default: latest
#   --env-file FILE      compose env file (default envs/.env.prod)
#   --services "a b"     render only: subset of auth gateway job search app profile notif (default: all)
#   --retries N          smoke-check attempts (default 30 compose / 40 render)
#   --interval SECS      seconds between attempts (default 5 compose / 15 render)
#   -h, --help
#
# Env (render target): RENDER_DEPLOY_HOOK_<SVC> (full hook URL incl. key, SVC upper-case: AUTH GATEWAY JOB
#   SEARCH APP PROFILE NOTIF) — never printed. Optional RENDER_SMOKE_URL_<SVC> (default https://jp-<svc>.onrender.com/health).
# Env (compose target): values from --env-file; smoke URL override COMPOSE_SMOKE_URL (default http://localhost:${GATEWAY_PORT:-5000}/health).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$INFRA_DIR/docker-compose.prod.yml"
ALL_RENDER_SVCS="auth gateway job search app profile notif"

DRY_RUN=0
TAG=""
ENV_FILE="$INFRA_DIR/envs/.env.prod"
SERVICES="$ALL_RENDER_SVCS"
RETRIES=""
INTERVAL=""
TARGET=""

log() { printf '[deploy] %s\n' "$*"; }
die() { printf '[deploy] ERROR: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '4,22p' "$0" | sed 's/^# \{0,1\}//'; }

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
    --services) [ $# -ge 2 ] || die "--services needs a value"; SERVICES="$2"; shift ;;
    --retries) [ $# -ge 2 ] || die "--retries needs a value"; RETRIES="$2"; shift ;;
    --interval) [ $# -ge 2 ] || die "--interval needs a value"; INTERVAL="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    compose|render) [ -z "$TARGET" ] || die "target given twice"; TARGET="$1" ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { usage >&2; die "missing target: compose|render"; }
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

deploy_render() {
  local retries="${RETRIES:-40}" interval="${INTERVAL:-15}" svc upper var hook sep url failed=0
  [ "$DRY_RUN" -eq 1 ] || command -v curl >/dev/null 2>&1 || die "curl not found"
  for svc in $SERVICES; do
    case " $ALL_RENDER_SVCS " in *" $svc "*) ;; *) die "unknown service '$svc' (valid: $ALL_RENDER_SVCS)" ;; esac
  done

  # Validate all hooks first so we never deploy half the stack because of a missing secret.
  for svc in $SERVICES; do
    upper="$(printf '%s' "$svc" | tr '[:lower:]' '[:upper:]')"
    var="RENDER_DEPLOY_HOOK_${upper}"
    if [ -z "${!var:-}" ]; then
      [ "$DRY_RUN" -eq 1 ] && log "dry-run: $var is not set (would fail on a real run)" || die "$var is not set"
    fi
  done

  for svc in $SERVICES; do
    upper="$(printf '%s' "$svc" | tr '[:lower:]' '[:upper:]')"
    var="RENDER_DEPLOY_HOOK_${upper}"
    hook="${!var:-<$var>}"
    sep='?'; case "$hook" in *\?*) sep='&' ;; esac
    if [ -n "$TAG" ]; then hook="${hook}${sep}ref=${TAG}"; fi
    log "trigger render deploy: jp-$svc${TAG:+ ref=$TAG}"
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[dry-run] curl -fsS -X POST <%s hidden>\n' "$var"
    else
      # URL holds the deploy key: pass via stdin config so it never shows in argv/process list or logs.
      printf 'url = "%s"\n' "$hook" | curl -fsS -o /dev/null --max-time 30 -X POST -K - \
        || { log "hook failed for jp-$svc"; failed=1; }
    fi
  done
  [ "$failed" -eq 0 ] || die "one or more deploy hooks failed"

  # Render free tier cold-starts / rebuilds take minutes: long retry window.
  for svc in $SERVICES; do
    upper="$(printf '%s' "$svc" | tr '[:lower:]' '[:upper:]')"
    var="RENDER_SMOKE_URL_${upper}"
    url="${!var:-https://jp-${svc}.onrender.com/health}"
    smoke "$url" "$retries" "$interval" || { log "smoke failed: $url"; failed=1; }
  done
  [ "$failed" -eq 0 ] || die "render smoke check failed — roll back via Render dashboard (Deploys > Rollback) or re-run with --tag <previous-sha>"
  log "render deploy OK"
}

case "$TARGET" in
  compose) deploy_compose ;;
  render) deploy_render ;;
esac
