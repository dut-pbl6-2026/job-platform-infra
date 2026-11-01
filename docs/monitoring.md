# Monitoring & Observability Architecture

This document describes the monitoring and observability architecture for the Vietnam Job Platform (`job-platform`), covering Prometheus, Grafana, OpenTelemetry instrumentation across .NET microservices, dashboard configurations, custom metric authoring, and alerting rules.

---

## 1. Architecture

```mermaid
flowchart LR
    subgraph DotNet["🟦 .NET Microservices (.NET 10)"]
        GW["job-platform-gateway :5000"]
        AUTH["job-platform-auth-svc :5001"]
        JOB["job-platform-job-svc :5002"]
        SEARCH["job-platform-search-svc :5003"]
        APP["job-platform-app-svc :5004"]
        PROFILE["job-platform-profile-svc :5005"]
        NOTIF["job-platform-notif-svc :5006"]
    end

    subgraph Monitoring["📊 Monitoring Stack"]
        PROM["Prometheus :9090\n(TSDB, 15s scrape interval, 7d retention)"]
        GRAF["Grafana :3001\n(Auto-provisioned Dashboards & Datasource)"]
    end

    GW -- "GET /metrics" --> PROM
    AUTH -- "GET /metrics" --> PROM
    JOB -- "GET /metrics" --> PROM
    SEARCH -- "GET /metrics" --> PROM
    APP -- "GET /metrics" --> PROM
    PROFILE -- "GET /metrics" --> PROM
    NOTIF -- "GET /metrics" --> PROM
    PROM -- "PromQL Query" --> GRAF
```

### Components

1. **OpenTelemetry SDK & Instrumentation (in each .NET service):**
   - In-process telemetry collection using `OpenTelemetry.Extensions.Hosting`, `OpenTelemetry.Instrumentation.AspNetCore`, `OpenTelemetry.Instrumentation.Http`, and `OpenTelemetry.Instrumentation.Runtime`.
   - Exposes Prometheus text-format scrape output via endpoint `GET /metrics` (`OpenTelemetry.Exporter.Prometheus.AspNetCore`).
2. **Prometheus Server (`job-platform-prometheus`):**
   - Scrapes all registered endpoints every 15 seconds.
   - For services running in Docker, targets bridge DNS names (e.g. `gateway:5000`, `auth:5001`).
   - For services run directly on the host (e.g. `dotnet run`), targets `host.docker.internal:<port>`.
   - TSDB retention set to 7 days for local development.
3. **Grafana (`job-platform-grafana`):**
   - Listens on host port `3001` (to prevent conflict with frontend React dev server on port 3000).
   - Automatically loads Prometheus datasource via provisioning (`docker/grafana/provisioning/datasources/prometheus.yml`).
   - Automatically loads dashboards from `docker/grafana/dashboards/` via dashboard provisioning.

---

## 2. Key Metrics Collected

### RED Metrics (Rate, Errors, Duration)

All HTTP inbound endpoints automatically track:
- `http_server_request_duration_seconds_count`: Total requests received.
- `http_server_request_duration_seconds_sum`: Total request execution duration.
- `http_server_request_duration_seconds_bucket`: Latency distribution buckets (p50, p95, p99).
- Labels: `http_response_status_code`, `http_route`, `http_request_method`, `service`.

### .NET Runtime Metrics

Collected via `OpenTelemetry.Instrumentation.Runtime` (exported from the .NET `System.Runtime` meter,
so the names below are the ones you will actually see on `/metrics`):

- `dotnet_gc_last_collection_heap_size_bytes`: Managed heap size per `gc_heap_generation` (`gen0`, `gen1`, `gen2`, `loh`).
- `dotnet_gc_collections_total`: Number of GC cycles completed per `gc_heap_generation`.
- `dotnet_thread_pool_thread_count_total`: Current worker/completion-port thread count.
- `dotnet_thread_pool_queue_length_total`: Pending work items in the thread pool queue.
- `dotnet_thread_pool_work_item_count_total`: Work items processed by the thread pool (counter).
- `dotnet_exceptions_total`: Thrown exceptions, labelled by `error_type`.
- `dotnet_process_cpu_time_seconds_total`: CPU time split by `cpu_mode` (`user`/`system`).
- `dotnet_process_memory_working_set_bytes`, `dotnet_assembly_count`, `dotnet_timer_count`: extra runtime detail.

> Several of these carry a `_total` suffix even though they are instantaneous values
> (`thread_pool_thread_count_total`). Use the raw value for those; use `rate()` only for the true counters.

> **Metric names are version-dependent.** They are defined by the OpenTelemetry runtime instrumentation and
> change between releases. Before editing a dashboard, scrape a service and confirm the name:
> `curl -s http://localhost:5003/metrics | grep '^# TYPE'`.

---

## 3. Accessing Monitoring Tools

| Tool | Host URL | Default Credentials | Description |
|------|----------|---------------------|-------------|
| **Grafana** | [http://localhost:3001](http://localhost:3001) | User: `admin`<br/>Pass: `admin` | Dashboards, visualizations, explorations |
| **Prometheus** | [http://localhost:9090](http://localhost:9090) | None | PromQL console & expression browser |
| **Prometheus Targets** | [http://localhost:9090/targets](http://localhost:9090/targets) | None | Health status of microservice scrapers |

> These URLs and the `admin`/`admin` login belong to the **local development** stack started by
> `docker compose up -d`; the ports are published on `localhost` only. Nothing here is deployed publicly —
> do not publish Grafana/Prometheus on a public interface, and change the Grafana password (or set
> `GF_SECURITY_ADMIN_PASSWORD`) before running the stack anywhere shared.

### Scrape target prerequisite — `/metrics` must be reachable

Each service exposes `GET /metrics` from the OpenTelemetry Prometheus exporter. Prometheus only collects from
a service whose app is actually listening on the expected port, so:

- Running in Docker: the compose service port must match `docker/prometheus/prometheus.yml` (e.g. `notif:5006`).
- Running on the host with `dotnet run`: the API's `Properties/launchSettings.json` pins the documented port
  (search `5003`, profile `5005`, notif `5006`). Prometheus scrapes those via `host.docker.internal:<port>`.

`/metrics` is disabled in the `Production` environment unless explicitly enabled:

| Setting | Default | Effect |
|---------|---------|--------|
| `METRICS_ENABLED` | `true` (non-Production), `false` (Production) | `false` ⇒ `GET /metrics` returns `404` |

Enable it for a production deployment (`METRICS_ENABLED=true`) only when the endpoint is reachable from the
Prometheus scrape network and not from the public internet; every service is otherwise publicly deployed, so
leaving it off keeps process/runtime internals out of the public surface.

---

## 4. Provisioned Dashboards

### 4.1 System Overview (`job-platform-overview`)

Designed for an on-call or operations engineer to quickly diagnose high-level platform health:
- **Service Health:** Instant stat cards showing `UP` (1, green) or `DOWN` (0, red) for all microservices (`up`).
- **Request Rate (req/s):** Throughput across services over a 5m sliding window (`sum(rate(http_server_request_duration_seconds_count{http_route!~"/metrics|/health"}[5m])) by (service)`). Scrape and probe traffic is excluded so the panel reflects real user requests.
- **Error Rate (5xx req/s):** Server failure rate (`http_response_status_code=~"5.."`, same route filter).
- **P95 Latency:** 95th percentile latency per service (`histogram_quantile(0.95, sum(rate(http_server_request_duration_seconds_bucket{http_route!~"/metrics|/health"}[5m])) by (le, service))`).
- **GC Heap Size:** `dotnet_gc_last_collection_heap_size_bytes` per `gc_heap_generation`.
- **Active Threads:** `dotnet_thread_pool_thread_count_total` per service.

### 4.2 .NET Runtime (`job-platform-dotnet-runtime`)

Designed for in-depth CLR debugging and performance profiling:
- **Service Selector:** Multi-select variable filtering metrics by microservice (`label_values(up, service)`).
- **GC Heap Size by Generation:** `dotnet_gc_last_collection_heap_size_bytes` broken down by `gc_heap_generation`.
- **GC Collection Rate:** `rate(dotnet_gc_collections_total[5m])` per generation.
- **ThreadPool Threads & Queue:** `dotnet_thread_pool_thread_count_total` vs `dotnet_thread_pool_queue_length_total`.
- **ThreadPool Completed Items / sec:** `rate(dotnet_thread_pool_work_item_count_total[5m])`.
- **Process CPU Usage:** `sum by (service) (rate(dotnet_process_cpu_time_seconds_total[5m]))`, split by `cpu_mode`.
- **Exception Rate:** `rate(dotnet_exceptions_total[5m])` per `error_type`.

---

## 5. Adding Custom Metrics

When adding business-specific counters or latency tracking in a service:

### Step 1: Define a `Meter`

```csharp
using System.Diagnostics.Metrics;

namespace Job.Infrastructure.Observability;

public static class JobDiagnostics
{
    public const string MeterName = "JobPlatform.JobService";
    public static readonly Meter Meter = new(MeterName, "1.0.0");

    public static readonly Counter<long> JobsCreatedCounter =
        Meter.CreateCounter<long>(
            name: "job_platform_jobs_created_total",
            unit: "jobs",
            description: "Total number of job postings created");
}
```

### Step 2: Register Meter in `Program.cs`

```csharp
builder.Services.AddOpenTelemetry()
    .WithMetrics(metrics =>
    {
        metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddRuntimeInstrumentation()
            .AddMeter("JobPlatform.JobService") // Register your custom Meter
            .AddPrometheusExporter();
    });
```

### Step 3: Record Measurements

```csharp
JobDiagnostics.JobsCreatedCounter.Add(1, new KeyValuePair<string, object?>("category", job.Category));
```

> **Cardinality Rule:** Never use unbounded strings (user IDs, emails, request UUIDs) as label values. Use low-cardinality tags (e.g. status code, category, provider name).

---

## 6. Recommended Alerting Rules

Alert on **symptoms users feel** (high error rate, excessive latency), not internal causes:

```yaml
groups:
  - name: service_symptom_alerts
    rules:
      - alert: HighHttpErrorRate
        expr: sum(rate(http_server_request_duration_seconds_count{http_route!~"/metrics|/health",http_response_status_code=~"5.."}[5m])) by (service)
              / sum(rate(http_server_request_duration_seconds_count{http_route!~"/metrics|/health"}[5m])) by (service) > 0.05
        for: 2m
        labels:
          severity: page
        annotations:
          summary: "Service {{ $labels.service }} has > 5% 5xx error rate"
          description: "High HTTP 5xx error rate observed on {{ $labels.service }} for over 2 minutes."

      - alert: HighP95Latency
        expr: histogram_quantile(0.95, sum(rate(http_server_request_duration_seconds_bucket{http_route!~"/metrics|/health"}[5m])) by (le, service)) > 2.0
        for: 3m
        labels:
          severity: page
        annotations:
          summary: "Service {{ $labels.service }} P95 latency > 2s"
          description: "P95 request latency on {{ $labels.service }} has exceeded 2 seconds for 3 minutes."

      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: page
        annotations:
          summary: "Service {{ $labels.service }} is DOWN"
          description: "Prometheus cannot scrape {{ $labels.service }} on target {{ $labels.instance }}."
```
