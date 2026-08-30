# Uptime Monitoring — Free (UptimeRobot 50 monitors, Grafana Cloud 10k metrics)

> Prod `jp-* onrender.com` Free sleeps 15m → cold start 1m. CI smoke `curl` weak. Use free external ping.

## UptimeRobot free (recommended)
- Create account app.uptimerobot.com → Add `HTTP(s)` monitor `https://jp-auth.onrender.com/health` interval `5m` → same for `jp-gateway /health`, `jp-job /health`, `jp-gateway/health/auth` via YARP.
- Alert via email/Slack free. 50 monitors covers 7 svc + gateway aggregated `GET /health`.
- Render Free 750h + Vercel 100GB already free; UptimeRobot free adds reliable `p95<500ms` check without paid Grafana.

## Grafana Cloud free (alternative)
- `GRAFANA_CLOUD_URL=__SET_VIA_INFISICAL__` `PROMETHEUS_URL=http://localhost:9090` (`envs/.env.prod.example`).
- Enable `Grafana Cloud 10k metrics` (SRS 9.3) `PERF-01 p95<500ms` via `prometheus.yml` scrape `postgres_exporter` thresholds `Supabase 400MB/15conn Upstash 8k Bonsai 800MB` `9-infra:305`.

## Sentry free (5k errs/mo)
- `SENTRY_DSN=__SET_VIA_INFISICAL__` `mise use sentry-cli` — add `Sentry SDK` to `Auth.Api Program.cs` `UseExceptionHandler` already.
- Not required for PBL6-16, enable after `profile/notif` scaffold.

## Smoke fallback
- CI `curl -sf https://jp-*.onrender.com/health` `sleep 60` handles cold start (see `auth ci.yml:88`).
