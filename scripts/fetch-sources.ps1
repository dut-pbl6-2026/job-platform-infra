<#
.SYNOPSIS
    Clone or update every service repo into job-platform-infra/.build/src (gitignored),
    the default build context of docker-compose.yml.

.DESCRIPTION
    Images are then built from a clean checkout of one ref (default: main), never from a
    developer's working tree with another branch or local edits checked out.
    .build/src is disposable: an existing checkout is hard-reset to the requested ref.
    To build from your own working trees instead, skip this script and set SERVICES_SRC=..

.PARAMETER Ref
    Branch or tag to check out in every repo. Default: main.

.EXAMPLE
    pwsh ./scripts/fetch-sources.ps1
    pwsh ./scripts/fetch-sources.ps1 -Ref main
#>
param([string]$Ref = "main")

$ErrorActionPreference = "Stop"
$Org = "dut-pbl6-2026"
$Repos = @(
    "job-platform-auth-svc", "job-platform-job-svc", "job-platform-search-svc",
    "job-platform-app-svc", "job-platform-profile-svc", "job-platform-notif-svc",
    "job-platform-ai-svc", "job-platform-gateway", "job-platform-web"
)

$InfraDir = Split-Path -Parent $PSScriptRoot
$SrcRoot = Join-Path $InfraDir ".build/src"
New-Item -ItemType Directory -Force -Path $SrcRoot | Out-Null
$SrcRoot = (Resolve-Path $SrcRoot).Path

foreach ($repo in $Repos) {
    $url = "https://github.com/$Org/$repo.git"
    $dir = Join-Path $SrcRoot $repo
    if (-not (Test-Path (Join-Path $dir ".git"))) {
        Write-Host "[clone] $repo ($Ref)"
        git clone --quiet --depth 1 --branch $Ref $url $dir
        if ($LASTEXITCODE -ne 0) { throw "clone failed: $repo" }
        continue
    }

    # Only reset a checkout that is ours: directly under .build/src and pointing at the org repo.
    $resolved = (Resolve-Path $dir).Path
    if ((Split-Path -Parent $resolved) -ne $SrcRoot) { throw "refusing to reset ${resolved}: not under $SrcRoot" }
    $remote = git -C $resolved remote get-url origin
    if ($remote -ne $url) { throw "refusing to reset ${resolved}: origin is $remote, expected $url" }

    Write-Host "[update] $repo ($Ref)"
    git -C $resolved fetch --quiet --depth 1 origin $Ref
    if ($LASTEXITCODE -ne 0) { throw "fetch failed: $repo" }
    git -C $resolved reset --quiet --hard FETCH_HEAD
    git -C $resolved clean --quiet -fdx
}

Write-Host ""
foreach ($repo in $Repos) {
    $sha = git -C (Join-Path $SrcRoot $repo) rev-parse --short HEAD
    Write-Host ("{0,-26} {1}" -f $repo, $sha)
}
Write-Host "`nNext: docker compose build && docker compose up -d"
