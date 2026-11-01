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

## Monitoring Stack (Prometheus + Grafana)

The monitoring stack collects OpenTelemetry metrics from all 7 .NET backend services and visualizes them on Grafana.

### Endpoints & Credentials

| Service | URL | Credentials | Purpose |
|---------|-----|-------------|---------|
| **Prometheus** | `http://localhost:9090` | _None_ | Metrics TSDB & scraper |
| **Prometheus Targets** | `http://localhost:9090/targets` | _None_ | Scrape health inspection |
| **Grafana** | `http://localhost:3001` | `admin` / `admin` | Dashboards & visualization |

> **Note:** Port `3001` is used for Grafana on the host (mapped to container port 3000) to avoid port collisions with the local React web frontend dev server.

### Dashboards

Dashboards are automatically provisioned from `docker/grafana/dashboards/`:

1. **Job Platform - System Overview** (`job-platform-overview`)
   - **Service Health:** Status of each target (`UP` / `DOWN`).
   - **Request Rate:** Aggregated requests/second per service (`http_server_request_duration_seconds_count`).
   - **Error Rate:** 5xx response rate per service.
   - **P95 Latency:** 95th-percentile response time computed across request duration buckets.
   - **GC Heap Size:** Heap memory usage per service.
   - **Active Threads:** ThreadPool thread counts.

2. **Job Platform - .NET Runtime** (`job-platform-dotnet-runtime`)
   - **GC Heap Size by Generation:** Gen 0, Gen 1, Gen 2, and LOH heap memory.
   - **GC Collections Rate:** Gen 0/1/2 collection frequencies.
   - **ThreadPool Threads & Queue:** Thread pool utilization and pending work queue length.
   - **Process CPU Usage & Exceptions:** Process CPU time rate and exception thrown rate.

See [docs/monitoring.md](docs/monitoring.md) for full monitoring architecture, adding custom metrics, and alert rules.

## Troubleshooting

- `port already allocated` → `docker compose down -v` or `lsof -i :5432`
- `mise run verify` not 14 → re-run `mise run sync-env`

See `envs/README.md` for Infisical fallback details.
