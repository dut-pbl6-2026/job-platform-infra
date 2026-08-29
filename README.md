# job-platform-infra

Docker Compose, K8s manifests, env sync — **Vietnam Job Platform** (`pbl6`) under [`dut-pbl6-2026`](https://github.com/dut-pbl6-2026).

- **Branch flow:** `feature/* → main` (see `job-platform-docs/.github/git-strategy.md`)
- **Jira:** `PBL6` on `skid.atlassian.net` — 8 sprints `W1-16`
- **Stack:** `.NET 10 LTS` `dotnet 10.0.100` via `mise`, `postgres:16` `redis:7` `elasticsearch:8.13.2` `kafka:3.7 KRaft`

## Prerequisites

- `mise` https://mise.jdx.dev `curl https://mise.run | sh` + `eval "$(mise activate bash)"` in `~/.bashrc`
- `docker` + `docker compose v2` `docker --version`
- `git` + `gh` `gh auth login`
- `dotnet 10.0.100` via `mise` (no manual install)
- `infisical` optional `mise exec -- infisical --version`

## Clone

```bash
mkdir -p ~/projects/personal/job-platform && cd ~/projects/personal/job-platform
for r in infra shared auth-svc job-svc search-svc app-svc profile-svc notif-svc gateway web mobile crawler ai-svc docs; do
  gh repo clone dut-pbl6-2026/job-platform-$r
done
```

## Setup

```bash
# 1. trust + install tools (run once per repo)
mise trust
mise install
dotnet --version  # 10.0.100
infisical --version

# 2. env sync — one command, no manual copy
./scripts/sync-env.sh dev      # copies envs/.env.dev.example -> envs/.env.dev -> ../job-platform-*/.env
# or
mise run sync-env
make sync-env

# verify
ls ../job-platform-*/.env | wc -l  # 14
make verify
cat envs/.env.dev | head -n 20
```

- Source `envs/.env.dev.example` committed (108 lines `JWT_SECRET` `DATABASE_URL*` `REDIS` `ES` `KAFKA`). Never commit `envs/.env.dev` or `../job-platform-*/.env` (`.gitignore`).
- Infisical `infisical login && infisical export --env=dev --path=/ --format=dotenv > envs/.env.dev` then `sync-env.sh` distributes. Fallback `cp .example` if no login. `mise.toml` `_.file=envs/.env.dev` auto-loads.
- Prod `mise run sync-env-prod` needs `infisical login` + `envs/.env.prod.example` `__SET_VIA_INFISICAL__`.

> Note: agent uses `mise exec -- dotnet ...` / `mise exec -- infisical ...` due to non-interactive shell without `mise activate`; humans just use `dotnet` / `infisical` after `mise install`.

## Docker Compose (PBL6-11)

```bash
docker compose up -d && docker compose ps   # postgres 5432, redis 6379, es 9200, kafka 9092, mailhog 1025/8025, kafka-ui 8080
docker compose logs -f                        # tail
docker compose down -v                        # reset volumes (re-runs docker/postgres/init.sql)
docker compose config -q                      # lint
```

- `docker-compose.yml` `env_file: envs/.env.dev`, `volumes pg_data/redis_data/es_data/kafka_data`, `network job-platform`, `healthcheck pg_isready/redis ping/curl _cluster/health/kafka-topics --list`, `kafka KRaft bitnami/kafka:3.7` topics `job-events,application-events` auto-create, `docker/postgres/init.sql` creates `job_platform_auth/job_platform_job/job_platform_app` + `pgcrypto`.

## Troubleshooting

- `mise trust` not run → `env not loaded`, `dotnet --version` fails → run `mise trust` per repo.
- `port already allocated` → `docker compose down -v` or `lsof -i :5432`.
- `ls ../job-platform-*/.env` not 14 → re-run `sync-env.sh dev`.
- `infisical login` fail → fallback to `cp envs/.env.dev.example envs/.env.dev`.

## Related Repos

14 repos: `job-platform-shared, *-auth-svc, *-job-svc, *-search-svc, *-app-svc, *-profile-svc, *-notif-svc, *-gateway, *-web, *-mobile, *-crawler, *-ai-svc, *-infra, *-docs`.
