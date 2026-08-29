# Envs — Single Source of Truth

All local env lives here, synced to 14 repos via one command.

```
job-platform/
  job-platform-infra/envs/.env.dev.example  ← committed template (this dir)
  job-platform-infra/envs/.env.dev          ← generated local (gitignored)
  job-platform-infra/scripts/sync-env.sh     ← sync to ../job-platform-*/.env
```

## Quick Start (new dev, TM1-4)

```bash
# 1. Clone all
gh repo clone dut-pbl6-2026/job-platform-infra
# ... clone other 13 under ~/projects/personal/job-platform/

# 2a. With Infisical (recommended, prod secrets)
infisical login
infisical pull --env=dev --path=/shared --format=dotenv > envs/.env.dev

# 2b. Without Infisical (free, dev only)
cp envs/.env.dev.example envs/.env.dev
# edit envs/.env.dev if needed (JWT_SECRET etc)

# 3. Sync to every repo (one command)
./scripts/sync-env.sh dev
# or: mise run sync-env

# 4. Verify
ls ../job-platform-*/.env  # 14 files, git-ignored
docker compose -f ../job-platform-infra/docker-compose.yml up -d
```

## Infisical Setup (TM1 once)

1. https://app.infisical.com → Org `dut-pbl6-2026` → Project `job-platform` → Envs `dev`/`prod`
2. Import `envs/.env.dev.example` as `dev` env keys, set `prod` secrets.
3. Invite TM2-4 (kenzoknz, chibaongunguoi, Khoa35734) via email.
4. Each TM: `infisical login && infisical init` in `job-platform-infra`.

## Git Rules

- `.env` (all) is `.gitignored` per repo.
- Only `envs/.env.*.example` is committed.
- Never commit `envs/.env.dev` or `INFISICAL_TOKEN` (kept in `mise.toml.local` gitignored).

## Related

- Branch flow: `job-platform-docs/.github/git-strategy.md`
- Master plan: `docs/master-plan.md:149`
