# job-platform-infra

Docker Compose, K8s manifests, env sync — **Vietnam Job Platform** (`pbl6`) under [`dut-pbl6-2026`](https://github.com/dut-pbl6-2026).

- **Branch flow:** `feature/* → main` (see `job-platform-docs/.github/git-strategy.md`)
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

## Docker Compose (PBL6-11)

```bash
docker compose up -d && docker compose ps   # postgres 5432, redis 6379, es 9200, kafka 9092, mailhog 1025/8025, kafka-ui 8080
docker compose logs -f                        # tail
docker compose down -v                        # reset volumes (re-runs docker/postgres/init.sql)
```

- `docker-compose.yml` env: `envs/.env.dev` (sync via `make sync-env`). Init: `docker/postgres/init.sql` creates `job_platform_auth/job_platform_job/job_platform_app` + `pgcrypto`.
- Healthchecks: `pg_isready`, `redis ping`, `es curl _cluster/health`, `kafka-topics --list`.
- Kafka KRaft `bitnami/kafka:3.7` topics `job-events,application-events` auto-create.

## Related Repos

14 repos: `job-platform-shared, *-auth-svc, *-job-svc, *-search-svc, *-app-svc, *-profile-svc, *-notif-svc, *-gateway, *-web, *-mobile, *-crawler, *-ai-svc, *-infra, *-docs`.
