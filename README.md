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

## Troubleshooting

- `port already allocated` → `docker compose down -v` or `lsof -i :5432`
- `mise run verify` not 14 → re-run `mise run sync-env`

See `envs/README.md` for Infisical fallback details.
