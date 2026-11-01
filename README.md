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

Prod stack = `docker-compose.prod.yml` (published GHCR images `ghcr.io/dut-pbl6-2026/job-platform-{auth-svc,job-svc,search-svc,app-svc,profile-svc,notif-svc,gateway,web}`, no dev-only services, no published DB ports, healthchecks + limits, required secrets via `${VAR:?}`). `scripts/deploy.sh compose` runs it on any docker host; `scripts/deploy.sh azure ...` drives an Azure VM.

```bash
# prod env (never commit): infisical export --env=prod --path=/ --format=dotenv > envs/.env.prod   (keys: envs/.env.prod.example)
docker compose --env-file envs/.env.prod -f docker-compose.prod.yml config -q   # lint
scripts/deploy.sh --dry-run compose      # preview
scripts/deploy.sh --tag <git-sha> compose  # pull + up -d --wait + smoke GET gateway /health (retries)
```

Image gaps: only auth-svc, gateway and job-svc workflows publish to GHCR today; search/app/profile/notif/web have no publish job yet, so `pull` fails for them until one is added (tags published: long sha + `latest`).

## Deploy on Azure (student credit)

Design: ONE Ubuntu 24.04 VM (Standard_B2ms, 2 vCPU / 8 GB, 64 GB StandardSSD) running the whole compose stack; start it only when testing, deallocate afterwards. Cost: ~$0.09/h compute while running (~$2 for a 24 h test day), only the disk (~$5-8/mo) + DNS-labelled dynamic IP while deallocated. A nightly `az vm auto-shutdown` (default 22:00 Vietnam time) is the safety net. Requires `az login` and an SSH key.

```bash
# 0. check what the student subscription allows (regions/SKUs/quota are restricted)
az vm list-skus -l southeastasia --size Standard_B2 --resource-type virtualMachines -o table
az vm list-usage -l southeastasia -o table | grep -i -E 'Total Regional|Standard B'
# 1. once: provision (idempotent; --dry-run first). Set AZURE_LOCATION if the region is not allowed.
export AZURE_ADMIN_CIDR=<your-ip>/32 AZURE_SUBSCRIPTION_ID=<sub-id>
scripts/azure-provision.sh --dry-run && scripts/azure-provision.sh     # prints the FQDN
# 2. each test session
export AZURE_RESOURCE_GROUP=rg-jobplatform AZURE_VM_NAME=vm-jobplatform AZURE_VM_SSH_USER=azureuser AZURE_SSH_KEY=~/.ssh/id_ed25519
scripts/deploy.sh --dry-run azure up
scripts/deploy.sh azure up               # start VM, wait SSH, sync compose+env, pull, up -d --wait, smoke http://<fqdn>:5000/health
scripts/deploy.sh azure status
scripts/deploy.sh azure down             # ALWAYS when finished: deallocate (add --compose-down to stop containers first)
```

- Rollback: `scripts/deploy.sh --tag <previous-sha> azure rollback` (re-syncs and redeploys pinned tag). Volumes persist across deallocate; never `down -v`.
- Rotate to the next student subscription: when credit runs low, `az login` with the next account, set `AZURE_SUBSCRIPTION_ID` (and a new `AZURE_RESOURCE_GROUP` if desired), re-run `azure-provision.sh`, then `azure up`. Data lives on the VM disk and does not migrate — seed again.
- Private GHCR packages: export `GHCR_USER` + `GHCR_TOKEN` (PAT `read:packages`); the token goes over ssh stdin, never argv.
- Reminder: a running VM burns credit 24/7 — deallocate after every session (stopping inside the OS does NOT stop billing, use `azure down`).

## Troubleshooting

- `port already allocated` → `docker compose down -v` or `lsof -i :5432`
- `mise run verify` not 14 → re-run `mise run sync-env`

See `envs/README.md` for Infisical fallback details.
