# Envs — Single Source of Truth

```
job-platform/
  job-platform-infra/envs/.env.dev.example  ← committed template (this dir)
  job-platform-infra/envs/.env.dev          ← generated local (gitignored)
  job-platform-infra/scripts/sync-env.sh     ← sync to ../job-platform-*/.env
```

## Quick Start

See `../README.md#setup` for clone and prerequisites. Env sync:

```bash
# With Infisical (preferred, pulls dev)
infisical login
mise run sync-env

# Without Infisical (fallback)
cp envs/.env.dev.example envs/.env.dev
mise run sync-env

mise run verify  # 14 files, git-ignored
```

Prod: `mise run sync-env-prod` (requires `infisical login`).

## Git Rules

- `.env` (all) is `.gitignored` per repo.
- Only `envs/.env.*.example` is committed.
- Never commit `envs/.env.dev` or `INFISICAL_TOKEN` (kept in `mise.toml.local` gitignored).

## Infisical Setup

See https://app.infisical.com — Org `dut-pbl6-2026`, Project `job-platform`, Envs `dev`/`prod`. Import `envs/.env.dev.example` as `dev` env keys.
