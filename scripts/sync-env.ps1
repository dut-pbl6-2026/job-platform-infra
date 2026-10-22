param (
    [string]$EnvName = "dev"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$infraDir = Split-Path -Parent $scriptDir
$envsDir = Join-Path $infraDir "envs"
$parentDir = Split-Path -Parent $infraDir

$target = Join-Path $envsDir ".env.$EnvName"
$example = Join-Path $envsDir ".env.$EnvName.example"

if (-not (Test-Path $target)) {
    if (Test-Path $example) {
        Write-Host "Copying $example -> $target"
        Copy-Item $example $target
    } else {
        Write-Error "Cannot find $target or $example"
        exit 1
    }
}

# Copy to infra .env
Copy-Item $target (Join-Path $infraDir ".env") -Force
Write-Host "Synced job-platform-infra/.env"

# Distribute to each git repo
$count = 0
Get-ChildItem -Path $parentDir -Directory -Filter "job-platform-*" | ForEach-Object {
    $repoPath = $_.FullName
    $repoName = $_.Name
    if (Test-Path (Join-Path $repoPath ".git")) {
        $destEnv = Join-Path $repoPath ".env"
        Copy-Item $target $destEnv -Force
        Write-Host "  synced $repoName/.env ($EnvName)"
        $count++
    }
}

Write-Host "Synced $count repos + infra/.env for env=$EnvName"
