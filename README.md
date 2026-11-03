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
docker compose up -d && docker compose ps   # default hybrid mode (infra + auth + gateway + web)

# All-in-one full stack (builds & runs all 6 microservices + gateway + web in Docker):
# docker compose -f docker-compose.full.yml up -d
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

> **Note:** Port `3001` is used for Grafana on the host (mapped to container port 3000) to avoid port collisions with the local React web frontend dev server. The `admin`/`admin` login is for **local development only** — set `GF_SECURITY_ADMIN_PASSWORD` before running this stack anywhere shared, and never expose Prometheus/Grafana publicly.

### Scrape targets

Prometheus scrapes each service on its documented port (`docker/prometheus/prometheus.yml`):
gateway `5000`, auth `5001`, job `5002`, search `5003`, app `5004`, profile `5005`, notif `5006`.
The host-run services (job `5002`, search `5003`, app `5004`, profile `5005`, notif `5006`) pin those ports in
`Properties/launchSettings.json`; gateway and auth are scraped as compose containers (`gateway:5000`, `auth:5001`).

`/metrics` is gated by configuration and **defaults to off in Production**:

| Setting | Default | Effect |
|---------|---------|--------|
| `METRICS_ENABLED` | `true` (non-Production), `false` (Production) | `false` ⇒ `GET /metrics` returns `404` |

Only enable it in a deployed environment (`METRICS_ENABLED=true`) when Prometheus can reach the service over
a private network — all 7 services are publicly deployed on Render, so leaving it off keeps runtime internals
out of the public surface.

### Dashboards

Dashboards are automatically provisioned from `docker/grafana/dashboards/`:

1. **Job Platform - System Overview** (`job-platform-overview`)
   - **Service Health:** Status of each target (`UP` / `DOWN`).
   - **Request Rate:** Aggregated requests/second per service (`http_server_request_duration_seconds_count`).
   - **Error Rate:** 5xx response rate per service.
   - **P95 Latency:** 95th-percentile response time computed across request duration buckets.
   - **GC Heap Size:** `dotnet_gc_last_collection_heap_size_bytes` per `gc_heap_generation`.
   - **Active Threads:** `dotnet_thread_pool_thread_count_total` per service.

2. **Job Platform - .NET Runtime** (`job-platform-dotnet-runtime`)
   - **GC Heap Size by Generation:** `dotnet_gc_last_collection_heap_size_bytes` split by `gc_heap_generation` (gen0/gen1/gen2/loh).
   - **GC Collections Rate:** `rate(dotnet_gc_collections_total[5m])` per generation.
   - **ThreadPool Threads & Queue:** `dotnet_thread_pool_thread_count_total` vs `dotnet_thread_pool_queue_length_total`.
   - **Process CPU Usage & Exceptions:** `rate(dotnet_process_cpu_time_seconds_total[5m])` and `rate(dotnet_exceptions_total[5m])`.

> Metric names come from the .NET `System.Runtime` meter and change between OpenTelemetry releases — confirm with
> `curl -s http://localhost:5003/metrics | grep '^# TYPE'` before editing a dashboard.

See [docs/monitoring.md](docs/monitoring.md) for full monitoring architecture, adding custom metrics, and alert rules.

## Troubleshooting

- `port already allocated` → `docker compose down -v` or `lsof -i :5432`
- `mise run verify` not 14 → re-run `mise run sync-env`

See `envs/README.md` for Infisical fallback details.
