<#
.SYNOPSIS
    Seed test data for JOB-01 (JOB-TC-01 through JOB-TC-09) directly into PostgreSQL.

.DESCRIPTION
    Tao du lieu kiem thu cho bo test case JOB-01:
      - Recruiter A  (recruiter-a@test.com / Test@1234)  + Company A (verified)
      - Recruiter B  (recruiter-b@test.com / Test@1234)  + Company B (verified)
      - Job Seeker   (seeker@test.com      / Test@1234)
      - 15 job postings cho Recruiter A (10 Active + 5 Pending) -- TC-07 pagination
      -  1 job posting cho Recruiter B                          -- TC-09 isolation

    Password duoc hash bang BCrypt work-factor 12 (khop PasswordHasherService.cs).
    Script tu dong tai BCrypt.Net-Next neu chua co trong nuget cache.
    Idempotent: chay nhieu lan khong bi loi (ON CONFLICT DO UPDATE).

.PREREQUISITES
    - Docker compose dang chay, postgres container healthy.
    - Ket noi Internet (chi can neu BCrypt chua co trong nuget cache).

.USAGE
    # Chay tu thu muc job-platform-infra:
    pwsh .\scripts\seed-test-data.ps1

    # Reset (xoa data cu roi tao lai):
    pwsh .\scripts\seed-test-data.ps1 -Reset

.PARAMETERS
    -Reset   Xoa test data cu truoc khi seed lai.
    -PgUser  PostgreSQL user   (default: postgres).
    -PgPass  PostgreSQL pass   (default: 123456 -- khop .env.dev).
#>
param(
    [switch]$Reset,
    [string]$PgUser = "postgres",
    [string]$PgPass = "123456"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Color helpers ────────────────────────────────────────────────────────────
function Write-Step { param($m) Write-Host "==> $m" -ForegroundColor Cyan   }
function Write-Ok   { param($m) Write-Host "    OK  $m" -ForegroundColor Green  }
function Write-Warn { param($m) Write-Host "  WARN  $m" -ForegroundColor Yellow }
function Write-Fail { param($m) Write-Host "  FAIL  $m" -ForegroundColor Red; exit 1 }

# ─── Load BCrypt.Net-Next (work-factor 12 == PasswordHasherService.cs) ────────
Write-Step "Loading BCrypt.Net-Next"

$bcryptDll = $null
$candidates = @(
    "$env:USERPROFILE\.nuget\packages\bcrypt.net-next\4.0.3\lib\net6.0\BCrypt.Net-Next.dll",
    "$env:USERPROFILE\.nuget\packages\bcrypt.net-next\4.0.3\lib\netstandard2.0\BCrypt.Net-Next.dll",
    [IO.Path]::GetFullPath("$PSScriptRoot\..\..\job-platform-auth-svc\src\Auth.Infrastructure\bin\Debug\net9.0\BCrypt.Net-Next.dll"),
    [IO.Path]::GetFullPath("$PSScriptRoot\..\..\job-platform-auth-svc\src\Auth.Infrastructure\bin\Release\net9.0\BCrypt.Net-Next.dll")
)
foreach ($c in $candidates) {
    if (Test-Path $c) { $bcryptDll = $c; break }
}

if (-not $bcryptDll) {
    Write-Warn "BCrypt.Net-Next not in nuget cache. Downloading via nuget.exe..."
    $tmp = Join-Path $env:TEMP "pbl6-bcrypt"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    $nugetExe = Join-Path $tmp "nuget.exe"
    if (-not (Test-Path $nugetExe)) {
        Write-Host "    Downloading nuget.exe..."
        Invoke-WebRequest "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" `
            -OutFile $nugetExe -UseBasicParsing
    }
    & $nugetExe install BCrypt.Net-Next -Version 4.0.3 -OutputDirectory $tmp -NonInteractive | Out-Null

    $bcryptDll = Get-ChildItem -Path $tmp -Filter "BCrypt.Net-Next.dll" -Recurse |
        Where-Object { $_.FullName -match "net6\.0|netstandard2" } |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $bcryptDll) { Write-Fail "Cannot find BCrypt.Net-Next.dll after nuget install." }
}

Add-Type -Path $bcryptDll
Write-Ok "Loaded: $bcryptDll"
function Get-BHash([string]$pw) { [BCrypt.Net.BCrypt]::HashPassword($pw, 12) }

# ─── Fixed GUIDs (predictable -- safe for idempotent re-runs) ────────────────
$RecruiterAId = "a1000000-0000-0000-0000-000000000001"
$RecruiterBId = "a2000000-0000-0000-0000-000000000002"
$SeekerId     = "a3000000-0000-0000-0000-000000000003"
$CompanyAId   = "c1000000-0000-0000-0000-000000000001"
$CompanyBId   = "c2000000-0000-0000-0000-000000000002"
$CategoryItId = "7d09cd31-5580-41a2-948e-00bfbfdc8e3b"    # IT -- from SeedData.cs
$JobBId       = "b9999999-0000-0000-0000-000000000099"
$TestPassword = "Test@1234"
$PgContainer  = "job-platform-postgres"

# ─── Check container ──────────────────────────────────────────────────────────
Write-Step "Checking Docker container '$PgContainer'"
$cStatus = docker inspect --format "{{.State.Status}}" $PgContainer 2>&1
if ($LASTEXITCODE -ne 0 -or $cStatus.Trim() -ne "running") {
    Write-Fail "Container '$PgContainer' is not running.`n  Start with: docker compose -f docker-compose.yml up -d postgres"
}
Write-Ok "Container running"

# ─── psql via docker exec (no local psql needed) ─────────────────────────────
function Invoke-Psql([string]$db, [string]$sql) {
    # Pipe SQL via stdin to avoid shell quoting nightmares with bcrypt $ chars
    $bytes  = [Text.Encoding]::UTF8.GetBytes($sql)
    $stream = [IO.MemoryStream]::new($bytes)

    $psi = [Diagnostics.ProcessStartInfo]::new("docker")
    $psi.Arguments        = "exec -i -e PGPASSWORD=$PgPass $PgContainer psql -U $PgUser -d $db"
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute  = $false

    $proc = [Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Write([Text.Encoding]::UTF8.GetString($bytes))
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        Write-Fail "psql [$db] failed (exit $($proc.ExitCode)):`n$stderr`n$stdout"
    }
    return $stdout
}

# ─── Optional reset ───────────────────────────────────────────────────────────
if ($Reset) {
    Write-Step "Reset: deleting existing test data"
    Invoke-Psql "job_platform_job" @"
DELETE FROM "Jobs"      WHERE "RecruiterId" IN ('$RecruiterAId','$RecruiterBId');
DELETE FROM "Companies" WHERE "Id"          IN ('$CompanyAId','$CompanyBId');
"@ | Out-Null
    Invoke-Psql "job_platform_auth" @"
DELETE FROM "Users" WHERE "Id" IN ('$RecruiterAId','$RecruiterBId','$SeekerId');
"@ | Out-Null
    Write-Ok "Old test data deleted"
}

# ─── Hash passwords (~3-4 s per hash at work-factor 12) ──────────────────────
Write-Step "Hashing passwords (BCrypt work-factor 12, ~3-4s each)..."
$HashA      = Get-BHash $TestPassword; Write-Ok "Recruiter A"
$HashB      = Get-BHash $TestPassword; Write-Ok "Recruiter B"
$HashSeeker = Get-BHash $TestPassword; Write-Ok "Job Seeker"

$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff")

# ─── 1. Users → job_platform_auth ────────────────────────────────────────────
Write-Step "Seeding users → job_platform_auth"
Invoke-Psql "job_platform_auth" @"
INSERT INTO "Users" ("Id","Email","PasswordHash","FullName","Role","company_id","IsActive","CreatedAt","UpdatedAt")
VALUES
  ('$RecruiterAId','recruiter-a@test.com','$HashA',     'Recruiter A','Recruiter','$CompanyAId',true,'$now','$now'),
  ('$RecruiterBId','recruiter-b@test.com','$HashB',     'Recruiter B','Recruiter','$CompanyBId',true,'$now','$now'),
  ('$SeekerId',    'seeker@test.com',     '$HashSeeker','Job Seeker', 'User',      NULL,         true,'$now','$now')
ON CONFLICT ("Id") DO UPDATE
  SET "PasswordHash" = EXCLUDED."PasswordHash",
      "UpdatedAt"    = EXCLUDED."UpdatedAt";
"@ | Out-Null
Write-Ok "recruiter-a@test.com  (Recruiter, CompanyId=$CompanyAId)"
Write-Ok "recruiter-b@test.com  (Recruiter, CompanyId=$CompanyBId)"
Write-Ok "seeker@test.com       (User / Job Seeker)"

# ─── 2. Companies → job_platform_job ─────────────────────────────────────────
Write-Step "Seeding companies → job_platform_job"
Invoke-Psql "job_platform_job" @"
INSERT INTO "Companies" ("Id","Name","Description","Verified","CreatedBy","CreatedAt","UpdatedAt")
VALUES
  ('$CompanyAId','Test Company A','Cong ty kiem thu A - da verified',true, '$RecruiterAId','$now','$now'),
  ('$CompanyBId','Test Company B','Cong ty kiem thu B - da verified',true, '$RecruiterBId','$now','$now')
ON CONFLICT ("Id") DO UPDATE
  SET "Verified"  = EXCLUDED."Verified",
      "UpdatedAt" = EXCLUDED."UpdatedAt";
"@ | Out-Null
Write-Ok "Test Company A  (ID=$CompanyAId  Verified=true)"
Write-Ok "Test Company B  (ID=$CompanyBId  Verified=true)"

# ─── 3. 15 jobs for Recruiter A (10 Active + 5 Pending) ─────────────────────
Write-Step "Seeding 15 jobs for Recruiter A (10 Active + 5 Pending)"
$rows = @()
for ($i = 1; $i -le 15; $i++) {
    $jid    = "b{0:D7}-0000-0000-0000-000000000000" -f $i
    $status = if ($i -le 10) { "Active" } else { "Pending" }
    $title  = "Test Job $i - Backend .NET Developer"
    $ts     = (Get-Date).ToUniversalTime().AddMinutes(-$i).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $rows  += "  ('$jid','$title','Mo ta kiem thu so $i','$CompanyAId','Da Nang','$RecruiterAId',15000000,25000000,'VND','$CategoryItId','Yeu cau $i',NULL,'FullTime','Middle','$status',0,'$ts','$ts')"
}
$vals = $rows -join ",`n"
Invoke-Psql "job_platform_job" @"
INSERT INTO "Jobs" (
    "Id","Title","Description","CompanyId","Location","RecruiterId",
    "SalaryMin","SalaryMax","SalaryCurrency","CategoryId","Requirements","Benefits",
    "EmploymentType","ExperienceLevel","Status","ViewCount","CreatedAt","UpdatedAt"
) VALUES
$vals
ON CONFLICT ("Id") DO UPDATE
  SET "Status"    = EXCLUDED."Status",
      "UpdatedAt" = EXCLUDED."UpdatedAt";
"@ | Out-Null
Write-Ok "Jobs #1-10 = Active  |  #11-15 = Pending  (all recruiter=$RecruiterAId)"

# ─── 4. 1 job for Recruiter B (TC-09 isolation) ──────────────────────────────
Write-Step "Seeding 1 job for Recruiter B (TC-09 isolation)"
Invoke-Psql "job_platform_job" @"
INSERT INTO "Jobs" (
    "Id","Title","Description","CompanyId","Location","RecruiterId",
    "SalaryMin","SalaryMax","SalaryCurrency","CategoryId","Requirements","Benefits",
    "EmploymentType","ExperienceLevel","Status","ViewCount","CreatedAt","UpdatedAt"
) VALUES (
    '$JobBId',
    'Recruiter B Job - MUST NOT appear in Recruiter A list',
    'Job cua Recruiter B - dung kiem thu TC-09 isolation.',
    '$CompanyBId','Ha Noi','$RecruiterBId',
    10000000,20000000,'VND','$CategoryItId',
    'Requirements B',NULL,'FullTime','Junior','Active',0,'$now','$now'
)
ON CONFLICT ("Id") DO UPDATE SET "UpdatedAt" = EXCLUDED."UpdatedAt";
"@ | Out-Null
Write-Ok "Recruiter B job  ID=$JobBId"

# ─── Summary ──────────────────────────────────────────────────────────────────
$line = "=" * 62
Write-Host ""
Write-Host $line -ForegroundColor Magenta
Write-Host "  SEED COMPLETE -- JOB-01 test data ready" -ForegroundColor Magenta
Write-Host $line -ForegroundColor Magenta
Write-Host ""
Write-Host "  Password (all accounts): $TestPassword" -ForegroundColor White
Write-Host ""
Write-Host "  ACCOUNTS:" -ForegroundColor Yellow
Write-Host "    Recruiter A : recruiter-a@test.com   (ID: $RecruiterAId)"
Write-Host "    Recruiter B : recruiter-b@test.com   (ID: $RecruiterBId)"
Write-Host "    Job Seeker  : seeker@test.com         (ID: $SeekerId)"
Write-Host ""
Write-Host "  COMPANIES:" -ForegroundColor Yellow
Write-Host "    Company A   : Test Company A   (ID: $CompanyAId, Verified=true)"
Write-Host "    Company B   : Test Company B   (ID: $CompanyBId, Verified=true)"
Write-Host ""
Write-Host "  JOBS:" -ForegroundColor Yellow
Write-Host "    Recruiter A : 15 jobs  (IDs b0000001... to b0000015...)"
Write-Host "                  #1-10  = Active  |  #11-15 = Pending"
Write-Host "    Recruiter B :  1 job  (ID: $JobBId, Active)"
Write-Host ""
Write-Host "  CATEGORY IT: $CategoryItId" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Newman/Postman environment variables:" -ForegroundColor Cyan
Write-Host "    recruiter_a_email  = recruiter-a@test.com"
Write-Host "    recruiter_b_email  = recruiter-b@test.com"
Write-Host "    seeker_email       = seeker@test.com"
Write-Host "    test_password      = $TestPassword"
Write-Host "    company_a_id       = $CompanyAId"
Write-Host "    company_b_id       = $CompanyBId"
Write-Host "    category_it_id     = $CategoryItId"
Write-Host "    recruiter_b_job_id = $JobBId"
Write-Host ""
Write-Host "  Reset: pwsh .\scripts\seed-test-data.ps1 -Reset" -ForegroundColor DarkGray
Write-Host ""
