# job-platform-infra

Docker Compose, K8s manifests, env sync — **Vietnam Job Platform** (`pbl6`) under [`dut-pbl6-2026`](https://github.com/dut-pbl6-2026).

- **Branch flow:** `feature/* → develop → release/* → main` (see `job-platform-docs/.github/git-strategy.md`)
- **Jira:** `PBL6` on `skid.atlassian.net` — 8 sprints `W1-16`
- **TM:** TM1 Hoai (infra/gateway), TM2 Thanh (job/search/crawler/ai), TM3 Chi Bao (web), TM4 Khoa (mobile)

## Env Sync — One Command (no manual copy)

```bash
# from this repo
./scripts/sync-env.sh dev      # dev: copies envs/.env.dev.example -> envs/.env.dev -> ../job-platform-*/.env
./scripts/sync-env.sh prod     # prod: needs infisical login

# or via mise / make
mise run sync-env   # or mise run sync-env-prod
make sync-env

# verify
ls ../job-platform-*/.env | wc -l  # 14
make verify
```

- Source: `envs/.env.dev.example` (committed) — single source, never `.env`.
- Generated: `envs/.env.dev`, `../job-platform-*/.env` (gitignored).
- Infisical (optional, free): `infisical login && infisical pull --env=dev --path=/shared --format=dotenv > envs/.env.dev` then `sync-env.sh` distributes. See `envs/README.md`.

## Related Repos

14 repos: `job-platform-shared, *-auth-svc, *-job-svc, *-search-svc, *-app-svc, *-profile-svc, *-notif-svc, *-gateway, *-web, *-mobile, *-crawler, *-ai-svc, *-infra, *-docs`.
