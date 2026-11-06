#!/usr/bin/env bash
set -euo pipefail

# fetch-sources.sh — clone or update every service repo into .build/src (gitignored), the default
# build context of docker-compose.yml. Images are built from a clean checkout of one ref, never
# from a working tree with another branch or local edits. .build/src is disposable: an existing
# checkout is hard-reset to the ref. To build from your own working trees, set SERVICES_SRC=..
# Usage: scripts/fetch-sources.sh [ref]   (default: main)

REF="${1:-main}"
ORG="dut-pbl6-2026"
REPOS=(
  job-platform-auth-svc job-platform-job-svc job-platform-search-svc
  job-platform-app-svc job-platform-profile-svc job-platform-notif-svc
  job-platform-ai-svc job-platform-gateway job-platform-web
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(dirname "$SCRIPT_DIR")/.build/src"
mkdir -p "$SRC_ROOT"
SRC_ROOT="$(cd "$SRC_ROOT" && pwd -P)"

for repo in "${REPOS[@]}"; do
  url="https://github.com/$ORG/$repo.git"
  dir="$SRC_ROOT/$repo"
  if [[ ! -d "$dir/.git" ]]; then
    echo "[clone] $repo ($REF)"
    git clone --quiet --depth 1 --branch "$REF" "$url" "$dir"
    continue
  fi

  # Only reset a checkout that is ours: directly under .build/src and pointing at the org repo.
  resolved="$(cd "$dir" && pwd -P)"
  [[ "$(dirname "$resolved")" == "$SRC_ROOT" ]] || { echo "refusing to reset $resolved: not under $SRC_ROOT" >&2; exit 1; }
  remote="$(git -C "$resolved" remote get-url origin)"
  [[ "$remote" == "$url" ]] || { echo "refusing to reset $resolved: origin is $remote, expected $url" >&2; exit 1; }

  echo "[update] $repo ($REF)"
  git -C "$resolved" fetch --quiet --depth 1 origin "$REF"
  git -C "$resolved" reset --quiet --hard FETCH_HEAD
  git -C "$resolved" clean --quiet -fdx
done

echo
for repo in "${REPOS[@]}"; do
  printf '%-26s %s\n' "$repo" "$(git -C "$SRC_ROOT/$repo" rev-parse --short HEAD)"
done
echo
echo "Next: docker compose build && docker compose up -d"
