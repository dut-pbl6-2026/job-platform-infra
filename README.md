# job-platform-infra

Docker Compose, K8s manifests, env sync — **Vietnam Job Platform** (`pbl6`) under [`dut-pbl6-2026`](https://github.com/dut-pbl6-2026).

## Prerequisites

- `mise` https://mise.jdx.dev
- `docker` + `docker compose v2`
- `git` + `gh` `gh auth login`
- `dotnet 10.0.100` via `mise` — `mise trust && mise install`

See `AGENTS.md` for shell activation (`mise activate`) and agent `mise exec` notes.

## Clone

```bash
mkdir -p ~/projects/personal/job-platform && cd ~/projects/personal/job-platform
for r in infra shared auth-svc job-svc search-svc app-svc profile-svc notif-svc gateway web mobile crawler ai-svc docs; do
  gh repo clone dut-pbl6-2026/job-platform-$r
done
```

## Setup

```bash
mise trust && mise install
mise run sync-env
mise run verify  # 14
```

Env: `envs/.env.dev.example` → `envs/.env.dev` → `../job-platform-*/.env` — see `envs/README.md`.

## Docker Compose

```bash
docker compose up -d && docker compose ps   # postgres 5432, redis 6379, es 9200, kafka 9092, mailhog 1025/8025, kafka-ui 8080
docker compose config -q                      # lint
```

## Production deploy

Prod stack = `docker-compose.prod.yml` (published GHCR images `ghcr.io/dut-pbl6-2026/job-platform-<svc>`, no dev-only services, no published DB ports, healthchecks + limits, required secrets via `${VAR:?}`) or Render (`render.yaml`, services `jp-*`). Both driven by `scripts/deploy.sh`.

```bash
# prod env (never commit): infisical export --env=prod --path=/ --format=dotenv > envs/.env.prod   (keys: envs/.env.prod.example)
docker compose --env-file envs/.env.prod -f docker-compose.prod.yml config -q   # lint
scripts/deploy.sh --dry-run compose                  # preview
scripts/deploy.sh compose                            # pull + up -d --wait + smoke GET gateway /health (retries)
scripts/deploy.sh --tag <git-sha> compose            # pin an image tag
RENDER_DEPLOY_HOOK_AUTH=... scripts/deploy.sh render # one hook env var per service, then smoke check jp-*.onrender.com/health
```

Rollback: re-run with the previous known-good tag, `scripts/deploy.sh --tag <previous-sha> compose` (Render: `--tag <sha>` passes `ref=`, or Dashboard > Deploys > Rollback). DB volumes are untouched by deploys; never use `down -v` in prod.

## Troubleshooting

- `port already allocated` → `docker compose down -v` or `lsof -i :5432`
- `mise run verify` not 14 → re-run `mise run sync-env`

See `envs/README.md` for Infisical fallback details.
