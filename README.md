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

Design: ONE Ubuntu 24.04 VM (Standard_B2ms, 2 vCPU / 8 GB, 64 GB StandardSSD) running the whole compose stack; provisioned once with Terraform (`terraform/`), then started only when testing and deallocated afterwards (`scripts/deploy.sh azure up|down`, or the `deploy-azure` workflow). Cost: ~$0.09/h compute while running (~$2 for a 24 h test day); while deallocated only the disk (~$5-8/mo) plus the Standard static public IP (~$3.6/mo) bill. A nightly auto-shutdown (default 22:00 Vietnam = 15:00 UTC) is the safety net. Stopping the VM from inside the OS does NOT stop billing: use `azure down`.

### 1. Provision (Terraform, once per subscription)

```bash
mise install                                  # terraform 1.9.8
az login && az account show --query id -o tsv # pick the student subscription
# Check what the student subscription allows (regions/SKUs/quota are restricted):
az vm list-skus -l southeastasia --size Standard_B2 --resource-type virtualMachines -o table
az vm list-usage -l southeastasia -o table | grep -i -E 'Total Regional|Standard B'

cd terraform
cp envs/sub1.tfvars.example envs/sub1.tfvars  # edit: subscription_id, ssh_public_key, admin_cidr (gitignored)
terraform init
terraform workspace select -or-create sub1    # one state per subscription (local backend)
terraform plan  -var-file=envs/sub1.tfvars
terraform apply -var-file=envs/sub1.tfvars    # prints fqdn, ssh_command, resource_group, vm_name
```

Optional remote state: `terraform/backend.azurerm.hcl.example` (one key per subscription, e.g. `-backend-config="key=sub1.tfstate"`). `scripts/azure-provision.sh` (az CLI, idempotent, `--dry-run`) is kept only as a no-Terraform fallback; Terraform is the supported path. Tear everything down with `terraform destroy -var-file=envs/sub1.tfvars` (deletes the disk/data).

### 2. Run tests on the VM

```bash
export AZURE_RESOURCE_GROUP=rg-jobplatformsub1 AZURE_VM_NAME=vm-jobplatformsub1 AZURE_VM_SSH_USER=azureuser AZURE_SSH_KEY=~/.ssh/id_ed25519
scripts/deploy.sh --dry-run azure up
scripts/deploy.sh azure up               # start VM, wait SSH, sync compose+env, pull, up -d --wait, smoke http://<fqdn>:5000/health
scripts/deploy.sh azure status
scripts/deploy.sh azure down             # ALWAYS when finished (add --compose-down to stop containers first)
```

- Rollback: `scripts/deploy.sh --tag <previous-sha> azure rollback`. Volumes persist across deallocate; never `down -v`.
- Private GHCR packages: export `GHCR_USER` + `GHCR_TOKEN` (PAT `read:packages`); the token goes over ssh stdin, never argv.

### 3. GitHub Actions

Workflows: `terraform.yml` (PR: fmt + validate always, plan only if configured; `workflow_dispatch` action=plan|apply, apply runs in Environment `production`) and `deploy-azure.yml` (`workflow_dispatch`: action up|down|status|rollback, image_tag, auto_deallocate_after_hours; Environment `production`; concurrency group `deploy-azure`; smoke `/health` and `/health/ready`, the latter enforced only when repo variable `REQUIRE_HEALTH_READY=true`).

Setup (OIDC, preferred):
```bash
az ad app create --display-name job-platform-gha                       # note appId
az ad sp create --id <appId>
az role assignment create --assignee <appId> --role Contributor --scope /subscriptions/<sub-id>/resourceGroups/rg-jobplatformsub1
# federated credentials (subject must match how the job runs):
#   repo:dut-pbl6-2026/job-platform-infra:environment:production   (deploy-azure, terraform apply)
#   repo:dut-pbl6-2026/job-platform-infra:pull_request             (terraform plan on PRs)
az ad app federated-credential create --id <appId> --parameters '{"name":"gha-prod","issuer":"https://token.actions.githubusercontent.com","subject":"repo:dut-pbl6-2026/job-platform-infra:environment:production","audiences":["api://AzureADTokenExchange"]}'
```
- Secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_SSH_PRIVATE_KEY`, `PROD_ENV_FILE` (full content of `envs/.env.prod`, from Infisical prod).
- Variables: `AZURE_RESOURCE_GROUP`, `AZURE_VM_NAME`, `AZURE_VM_SSH_USER`, `TF_SSH_PUBLIC_KEY`, `TF_ADMIN_CIDR` (use a CIDR that covers GitHub runners only if you want CI SSH, otherwise run deploys locally), remote state `TFSTATE_RESOURCE_GROUP` / `TFSTATE_STORAGE_ACCOUNT` / `TFSTATE_CONTAINER` / `TFSTATE_KEY` (CI plan/apply require remote state), optional `GATEWAY_PORT`, `REQUIRE_HEALTH_READY`.
- Settings > Environments > `production`: add required reviewers (gates deploy and apply).
- Caveat: GitHub-hosted runner IPs are not in `admin_cidr`, so CI SSH to the VM needs port 22 reachable from runners (widen `admin_cidr` temporarily, or use a self-hosted runner). Student tenants may forbid app registrations (`az ad app create` fails): then use the SSH-only fallback below.
- Fallback without OIDC/az (student tenant forbids app registrations): leave the three AZURE_* OIDC secrets unset and set `AZURE_VM_HOST` (variable) + `AZURE_SSH_PRIVATE_KEY` + `PROD_ENV_FILE`. The workflow then runs `deploy.sh` with `AZURE_SKIP_VM_POWER=1` against an already running VM (only `up`/`rollback`; start/deallocate need `az`, do them locally with `scripts/deploy.sh azure up|down` or the portal).
- Auto-deallocate: no `sleep` jobs. `auto_deallocate_after_hours=N` (OIDC mode) re-sets the VM's native Azure auto-shutdown to now+N hours (daily recurrence), and the Terraform nightly schedule remains the fallback; a later `terraform apply` resets it to `auto_shutdown_time`.

### 4. Rotating student subscriptions

Each of the 3 subscriptions has its own tfvars (`envs/sub1|sub2|sub3.tfvars`) and its own Terraform workspace/state key. When credit runs low: `az login` into the next account, `terraform workspace select -or-create sub2`, `terraform apply -var-file=envs/sub2.tfvars`, update `AZURE_*` env vars/secrets (subscription id, resource group `rg-<prefix>`, VM name `vm-<prefix>`), run `deploy.sh azure up`. Data does not migrate between subscriptions: re-seed. `terraform destroy` the exhausted one if still allowed.

## Troubleshooting

- `port already allocated` → `docker compose down -v` or `lsof -i :5432`
- `mise run verify` not 14 → re-run `mise run sync-env`

See `envs/README.md` for Infisical fallback details.
