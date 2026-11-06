#Requires -Version 7
<#
.SYNOPSIS
    Seed the local compose stack with demo companies, accounts and jobs (dev only). Safe to re-run.

.DESCRIPTION
    - Companies: inserted straight into job_platform_job with fixed ids. There is no way to create
      the first company through the API (POST /api/companies needs a Recruiter, and registering a
      Recruiter needs an existing company).
    - Accounts (password -Password, default Abc12345):
        admin@jobplatform.local      Admin (registered as User, then promoted in job_platform_auth:
                                     auth-svc has no API to create an admin)
        recruiter@jobplatform.local  Recruiter of the first company
        user@jobplatform.local       User (candidate)
    - Jobs: created by the recruiter through the gateway, then approved by the admin through the
      gateway, so they reach search-svc over Kafka like real jobs. The last -PendingJobs jobs stay
      Pending for testing approve/reject.

.EXAMPLE
    pwsh ./scripts/seed-dev.ps1
#>
param(
    [string]$Gateway = "http://localhost:5000",
    [string]$Password = "Abc12345",
    [int]$PendingJobs = 2,
    [string]$PostgresContainer = "job-platform-postgres"
)

$ErrorActionPreference = "Stop"
$Api = "$Gateway/api"

function Invoke-Api([string]$Method, [string]$Path, $Body = $null, [string]$Token = $null) {
    $headers = @{}
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    $params = @{ Method = $Method; Uri = "$Api$Path"; Headers = $headers; SkipHttpErrorCheck = $true; StatusCodeVariable = "code" }
    if ($null -ne $Body) {
        $params.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 5))
        $params.ContentType = "application/json; charset=utf-8"
    }
    $res = Invoke-RestMethod @params
    return [pscustomobject]@{ Code = [int]$code; Body = $res }
}

function Invoke-Sql([string]$Db, [string]$Sql) {
    $out = $Sql | docker exec -i $PostgresContainer psql -U postgres -d $Db -v ON_ERROR_STOP=1 -At
    if ($LASTEXITCODE -ne 0) { throw "psql failed on $Db" }
    return $out
}

function Get-Token([string]$Email) {
    $r = Invoke-Api POST "/auth/login" @{ email = $Email; password = $Password }
    if ($r.Code -ne 200) { throw "login $Email -> $($r.Code)" }
    return $r.Body.accessToken
}

function Register([string]$Email, [string]$FullName, [string]$Role, [string]$CompanyId = $null) {
    $body = @{ email = $Email; password = $Password; fullName = $FullName; role = $Role }
    if ($CompanyId) { $body.companyId = $CompanyId }
    $r = Invoke-Api POST "/auth/register" $body
    if ($r.Code -eq 201 -or $r.Code -eq 200) { Write-Host "[account] $Email created ($Role)" }
    elseif ($r.Code -eq 409) { Write-Host "[account] $Email already exists" }
    else { throw "register $Email -> $($r.Code): $($r.Body | ConvertTo-Json -Compress)" }
}

# ── 0. Stack is up ───────────────────────────────────────────────────────────
$health = Invoke-Api GET "/health"
if ($health.Code -ne 200) { throw "gateway not reachable at $Gateway (docker compose up -d first)" }
$down = @($health.Body.services | Where-Object status -ne "UP" | ForEach-Object name)
if ($down.Count) { throw "services not UP yet: $($down -join ', ')" }

# ── 1. Companies (fixed ids, idempotent) ──────────────────────────────────────
$companies = @(
    @{ Id = "11111111-1111-4111-8111-111111111111"; Name = "Công ty Phần mềm Sông Hàn"; Industry = "Công nghệ thông tin"; Address = "Hải Châu, Đà Nẵng"; Website = "https://songhan.example.vn"; Size = "100-499" },
    @{ Id = "22222222-2222-4222-8222-222222222222"; Name = "Ngân hàng Thương mại Hòa Bình"; Industry = "Tài chính - Ngân hàng"; Address = "Hoàn Kiếm, Hà Nội"; Website = "https://hoabinhbank.example.vn"; Size = "1000+" },
    @{ Id = "33333333-3333-4333-8333-333333333333"; Name = "Khách sạn Biển Xanh"; Industry = "Nhà hàng - Khách sạn"; Address = "Quận 1, TP. Hồ Chí Minh"; Website = "https://bienxanh.example.vn"; Size = "100-499" }
)
$systemUser = "00000000-0000-4000-8000-000000000001"
foreach ($c in $companies) {
    $name = $c.Name.Replace("'", "''")
    Invoke-Sql "job_platform_job" @"
INSERT INTO "Companies" ("Id","Name","Verified","Website","Description","Address","Industry","Size","CreatedAt","UpdatedAt","CreatedBy")
VALUES ('$($c.Id)','$name',true,'$($c.Website)','Dữ liệu mẫu cho môi trường dev.','$($c.Address)','$($c.Industry)','$($c.Size)',now(),now(),'$systemUser')
ON CONFLICT ("Id") DO NOTHING;
"@ | Out-Null
}
Write-Host "[company] $($companies.Count) demo companies present"

# ── 2. Accounts ───────────────────────────────────────────────────────────────
Register "admin@jobplatform.local" "Quản trị viên" "User"
Invoke-Sql "job_platform_auth" "UPDATE `"Users`" SET `"Role`"='Admin' WHERE `"Email`"='admin@jobplatform.local' AND `"Role`"<>'Admin';" | Out-Null
Register "recruiter@jobplatform.local" "Nhà tuyển dụng Sông Hàn" "Recruiter" $companies[0].Id
Register "user@jobplatform.local" "Nguyễn Văn An" "User"

$recruiterToken = Get-Token "recruiter@jobplatform.local"
$adminToken = Get-Token "admin@jobplatform.local"

# ── 3. Jobs (only when the recruiter has none yet) ────────────────────────────
$mine = Invoke-Api GET "/jobs/recruiter?page=1&size=1" $null $recruiterToken
$existing = if ($mine.Body.total) { [int]$mine.Body.total } else { 0 }
if ($existing -gt 0) {
    Write-Host "[job] recruiter already has $existing jobs, skipping creation"
} else {
    $cats = @{}
    (Invoke-Api GET "/categories").Body | ForEach-Object { $cats[$_.name] = $_.id }
    $companyId = $companies[0].Id
    $jobs = @(
        @("Lập trình viên .NET (Backend)", "IT", "Đà Nẵng", 15000000, 25000000, "FullTime", "Mid"),
        @("Kỹ sư Frontend React", "IT", "Đà Nẵng", 12000000, 22000000, "FullTime", "Mid"),
        @("Thực tập sinh Kiểm thử phần mềm", "IT", "Đà Nẵng", 3000000, 5000000, "Internship", "Entry"),
        @("Trưởng nhóm DevOps", "IT", "Hà Nội", 35000000, 50000000, "FullTime", "Lead"),
        @("Chuyên viên Phân tích dữ liệu", "Finance", "Hà Nội", 18000000, 28000000, "FullTime", "Senior"),
        @("Nhân viên Kinh doanh phần mềm", "Sales", "TP. Hồ Chí Minh", 10000000, 20000000, "FullTime", "Entry"),
        @("Chuyên viên Marketing nội dung", "Marketing", "TP. Hồ Chí Minh", 0, 0, "PartTime", "Mid"),
        @("Kỹ sư Hệ thống nhúng", "Engineering", "Đà Nẵng", 20000000, 30000000, "Contract", "Senior")
    )
    foreach ($j in $jobs) {
        $body = @{
            title = $j[0]; companyId = $companyId; location = $j[2]
            description = "Mô tả công việc: tham gia phát triển sản phẩm cùng đội ngũ $($companies[0].Name). Làm việc tại $($j[2])."
            requirements = "Có kỹ năng phù hợp vị trí $($j[0]); giao tiếp tốt; chủ động trong công việc."
            benefits = "Lương tháng 13, bảo hiểm đầy đủ, 12 ngày phép mỗi năm."
            categoryId = $cats[$j[1]]; employmentType = $j[5]; experienceLevel = $j[6]; salaryCurrency = "VND"
        }
        if ($j[3] -gt 0) { $body.salaryMin = $j[3]; $body.salaryMax = $j[4] }
        $r = Invoke-Api POST "/jobs" $body $recruiterToken
        if ($r.Code -ne 201 -and $r.Code -ne 200) { throw "create job '$($j[0])' -> $($r.Code): $($r.Body | ConvertTo-Json -Compress)" }
    }
    Write-Host "[job] created $($jobs.Count) jobs (Pending)"
}

# ── 4. Approve all but the last -PendingJobs pending jobs ──────────────────────
$pending = Invoke-Api GET "/admin/jobs?status=Pending&page=1&size=100" $null $adminToken
if ($pending.Code -ne 200) { throw "list pending jobs -> $($pending.Code)" }
# job-svc admin lists use the auth-style envelope { data, pagination }.
$items = @($(if ($null -ne $pending.Body.data) { $pending.Body.data } else { $pending.Body.items }) | Sort-Object createdAt)
$toApprove = if ($items.Count -gt $PendingJobs) { $items[0..($items.Count - $PendingJobs - 1)] } else { @() }
foreach ($job in $toApprove) {
    $r = Invoke-Api POST "/admin/jobs/$($job.id)/approve" @{ note = "Seed dev" } $adminToken
    if ($r.Code -ge 300) { throw "approve $($job.id) -> $($r.Code)" }
}
Write-Host "[job] approved $($toApprove.Count), left $([math]::Min($items.Count, $PendingJobs)) Pending for review"

# ── 5. Wait for search-svc to index the approved jobs ─────────────────────────
# Expected: every Active job of the recruiter (all of them minus the ones left Pending).
$all = (Invoke-Api GET "/jobs/recruiter?page=1&size=1" $null $recruiterToken).Body.total
$expected = [math]::Max(0, [int]$all - [math]::Min($items.Count, $PendingJobs))
for ($i = 0; $i -lt 30; $i++) {
    # Vary the page size so a cached result from an earlier poll is never reused.
    $total = (Invoke-Api GET "/search/jobs?page=0&size=$($i + 1)").Body.total
    if ($total -ge $expected) { break }
    Start-Sleep -Seconds 2
}
Write-Host "[search] $total of $expected approved jobs searchable"
Write-Host "`nDone. Web: http://localhost:5173   (password for all demo accounts: $Password)"
