#!/usr/bin/env bash
set -euo pipefail

# sync-env.sh — One-command env sync for 14-repo job-platform
# ORG guard: only dut-pbl6-2026, local-only (techsoft never touched)
ORG="${ORG:-dut-pbl6-2026}"
if [[ "$ORG" != "dut-pbl6-2026" ]]; then
  echo "Abort: ORG must be dut-pbl6-2026 (got $ORG)" >&2
  exit 1
fi
# Ensure not inside techsoft-code check (local-only)
if grep -qr "techsoft" --include="*.sh" . 2>/dev/null | grep -v "techsoft.*never"; then
  echo "Guard: techsoft string found in scripts — abort" >&2
  exit 1
fi

ENV_NAME="${1:-dev}"
if [[ "$ENV_NAME" != "dev" && "$ENV_NAME" != "prod" ]]; then
  echo "Usage: $0 [dev|prod]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$INFRA_DIR/envs"
PARENT_DIR="$(dirname "$INFRA_DIR")"  # ~/projects/personal/job-platform

EXAMPLE="$ENVS_DIR/.env.$ENV_NAME.example"
TARGET="$ENVS_DIR/.env.$ENV_NAME"

# 1. Ensure ENVS_DIR/.env.<env> exists: Infisical preferred, fallback to example
# Always try Infisical if available; fallback to example if empty or failed
INFISICAL_BIN=""
if command -v infisical >/dev/null 2>&1; then
  INFISICAL_BIN="infisical"
elif command -v mise >/dev/null 2>&1 && mise exec -- infisical --help >/dev/null 2>&1; then
  INFISICAL_BIN="mise exec -- infisical"
fi
if [[ -n "$INFISICAL_BIN" ]] && $INFISICAL_BIN --help >/dev/null 2>&1; then
  echo "Infisical detected ($INFISICAL_BIN) — pulling $ENV_NAME env from Infisical..."
  INFISICAL_PATH="${INFISICAL_PATH:-/}"
  TMP_TARGET="$(mktemp)"
  if (cd "$INFRA_DIR" && $INFISICAL_BIN export --env="$ENV_NAME" --path="$INFISICAL_PATH" --format=dotenv > "$TMP_TARGET" 2>/dev/null); then
    # If Infisical returns empty (no secrets at path), fallback to example
    if [[ -s "$TMP_TARGET" ]] && grep -q "=" "$TMP_TARGET" 2>/dev/null; then
      cp "$TMP_TARGET" "$TARGET"
      echo "Pulled $ENV_NAME from Infisical ($INFISICAL_PATH) -> $TARGET ($(wc -l < "$TARGET") lines)"
    else
      echo "Infisical returned empty for path $INFISICAL_PATH (no secrets yet) — falling back to $EXAMPLE"
      cp "$EXAMPLE" "$TARGET"
    fi
    rm -f "$TMP_TARGET"
  else
    echo "Infisical export failed for path $INFISICAL_PATH (not logged in?) — falling back to $EXAMPLE"
    cp "$EXAMPLE" "$TARGET"
  fi
else
  if [[ -f "$TARGET" ]]; then
    echo "Using existing $TARGET (Infisical not installed)"
  else
    echo "Infisical not installed — copying $EXAMPLE -> $TARGET"
    cp "$EXAMPLE" "$TARGET"
  fi
fi

# 2. Distribute to every job-platform-*/.env (gitignored)
count=0
for repo_dir in "$PARENT_DIR"/job-platform-*; do
  # Skip files, only dirs that are git repos
  if [[ -d "$repo_dir/.git" ]]; then
    # Backup existing .env if present
    if [[ -f "$repo_dir/.env" ]]; then
      cp "$repo_dir/.env" "$repo_dir/.env.bak.$ENV_NAME" 2>/dev/null || true
    fi
    cp "$TARGET" "$repo_dir/.env"
    echo "  synced $(basename "$repo_dir")/.env ($ENV_NAME)"
    count=$((count+1))
  fi
done

# Also keep infra's own .env for compose
cp "$TARGET" "$INFRA_DIR/.env" 2>/dev/null || true
echo "Synced $count repos + infra/.env for env=$ENV_NAME"

# 3. Mise hint
if command -v mise >/dev/null 2>&1; then
  echo "Tip: mise will auto-load envs/.env.$ENV_NAME if mise.toml present (mise trust)"
fi

echo "Done. Verify: ls $PARENT_DIR/job-platform-*/.env | wc -l should be $count"
# Safety: ensure techsoft never in synced files
if grep -qi "techsoft" "$TARGET" 2>/dev/null; then
  echo "Warning: techsoft found in env — remove it" >&2
  exit 1
fi
