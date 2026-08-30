# AGENTS — job-platform-infra

> Env + compose single source. SRS: `job-platform-docs/docs/master-plan.md`, `docs/srs/en/{6-nfr,8-system-architecture,9-infra-cost-analysis,3-must-have-fr}`. Git: `job-platform-docs/.github/git-strategy.md` (`feature/* → main`).

## Mise activation

Activate `mise` for bare `dotnet`/`infisical` without `mise exec`:

| Shell | Add to config file | Activate |
|-------|--------------------|----------|
| `bash` | `~/.bashrc` or `~/.bash_profile` | `eval "$(mise activate bash)"` |
| `zsh` | `~/.zshrc` | `eval "$(mise activate zsh)"` |
| `fish` | `~/.config/fish/config.fish` | `mise activate fish \| source` |
| `PowerShell` | `$PROFILE` | `mise activate pwsh \| Out-String \| Invoke-Expression` |

Agent uses `mise exec -- dotnet ...` / `mise exec -- infisical ...` due to non-interactive shell without `mise activate`; humans just use `dotnet` / `infisical` after `mise install`.

## Scope

Docker Compose, K8s manifests (NICE), env sync — Vietnam Job Platform (`pbl6`) `dut-pbl6-2026`. Priority MUST: `DOCK-01`/`DB-01` (SRS 3), SHOULD `KAFKA-01`/`CACHE-01`, NICE `K8S-01`.

## Env — single source of truth

- Template `envs/.env.dev.example` (108 lines, committed) → `envs/.env.dev` (gitignored) → `../job-platform-*/.env` + `/.env` via `mise run sync-env` (`scripts/sync-env.sh dev`, Org `dut-pbl6-2026` gate). Prod `mise run sync-env-prod` requires `infisical login` + `envs/.env.prod.example` (`__SET_VIA_INFISICAL__`).
- Never commit `.env` / `INFISICAL_TOKEN` (`.gitignore`, `mise.toml.local`). `mise.toml: [env] _.file="envs/.env.dev"` auto-loads after `mise trust`.
- Infisical: Org `dut-pbl6-2026` Project `job-platform` Envs `dev`/`prod` — `infisical export --env=dev --path=/ --format=dotenv` (agent: `mise exec -- infisical ...`). Fallback `cp envs/.env.dev.example envs/.env.dev` if no login. See `envs/README.md`.

## Docker Compose (PBL6-11, `DB-01`)

Services `docker-compose.yml` (`name: job-platform`, `network job-platform` bridge):
`postgres:16-alpine` 5432 (`pg_data` + `docker/postgres/init.sql` → `job_platform_auth/job_platform_job/job_platform_app` + `pgcrypto`, `healthcheck pg_isready`), `redis:7` 6379 (`redis ping`), `elasticsearch:8.13.2` 9200 single-node `xpack.security.enabled=false`, `kafka:3.7` KRaft 9092/9093 topics `job-events,application-events`, `kafka-ui` 8080, `mailhog` 1025/8025.

```bash
mise trust && mise install
mise run sync-env
mise run verify  # 14
docker compose up -d && docker compose ps
docker compose config -q  # lint
docker compose down -v    # reset volumes (re-runs init.sql)
```

## K8s / deployment (SRS 8.6, 9)

- Local: Compose hot-reload + `env_file`. Staging `Render Free 750h + Vercel` + `Supabase` 500MB + `Upstash` Redis + `Bonsai` ES 1GB + `Confluent` Kafka + `R2` 10GB — zero-cost (`docs/srs/en/9-infra-cost-analysis.md`).
- K8s NICE `K8S-01` (`docs/srs/en/5-nice-have-fr.md`) — manifests `Deployment/Service/Ingress/ConfigMap/Secret/HPA` not yet in repo; keep Compose parity, no hard-coded env vars (`docs/srs/en/6-nfr.md:PORT-02`).
- CI `.github/workflows/ci.yml`: `cp .example→.env.dev`, `docker compose config -q`, `grep job_platform_auth`.

## 2026 best practice (NFR `6-nfr.md:MAINT`)

- IaC + stateless + DB-per-service (`docs/srs/en/8-system-architecture.md`), ACID + connection pooling, retry 3 exp backoff, circuit breaker, `GET /api/health` per svc aggregated via gateway.
- Logging JSON `ERROR/WARN/INFO/DEBUG`, metrics `PERF-01 p95<500ms` via Grafana, `SEC-04 TLS1.2+`, `SEC-08` secrets via K8s Secret, `PORT-01` multi-OS via Docker.
- Keep `docker-compose.yml` header minimal (`# … — see README.md`), single source `master-plan.md:149,196,222,271`.

## Workflow

`feature/* → main` (`job-platform-docs/.github/git-strategy.md`), `mise run verify` not 14 → re-run `mise run sync-env`, `port already allocated` → `docker compose down -v` or `lsof -i :5432`.
