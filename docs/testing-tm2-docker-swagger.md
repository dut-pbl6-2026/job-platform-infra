# HƯỚNG DẪN KIỂM THỬ PHẦN VIỆC TM2 — DOCKER + SWAGGER

> **Thành viên:** TM2 — Nguyễn Chí Thanh (git: `Nguyen Thanh`) — *Backend + Tìm kiếm + AI*
> **Nguồn đối chiếu:** SRS `job-platform-docs/docs/srs/vi/*` (mục 3.3, 3.4, 3.6, 3.10, 4.5, 5.x), `master-plan.vi.md`, và lịch sử commit trong các repo.
> **Đường dẫn:** các lệnh giả định workspace đặt tại `D:\Code\pbl6` (chứa các repo `job-platform-*` cạnh nhau) — thay bằng đường dẫn của bạn.
> **Mục tiêu:** dựng toàn bộ hệ thống bằng Docker, rồi kiểm thử từng tính năng TM2 đã làm qua **Swagger UI**, Kafka UI, MailHog, Elasticsearch, Prometheus/Grafana.

---

## 1. TÓM TẮT PHẦN VIỆC TM2

### 1.1 Trách nhiệm theo SRS

| ID SRS | Thành phần | Tuần | Mức ưu tiên |
|:--|:--|:--|:--|
| JOB-01 | Job Service — CRUD tin, danh mục, công ty | 2 | Bắt buộc |
| SEARCH-01 | Search Service — tìm kiếm từ khóa, địa điểm, phân trang | 2 | Bắt buộc |
| PROFILE-01 | Profile Service — hồ sơ, kỹ năng, kinh nghiệm, học vấn | 3 | Bắt buộc |
| CRAWL-01 | Crawler — thu thập 500+ tin từ vieclam.gov.vn | 4 | Bắt buộc |
| ADV-01 | Tìm kiếm nâng cao — lọc lương/kỹ năng/loại hình, phân tích tiếng Việt | 6 | Nên có |
| — | Kafka consumer, đồng bộ ES, Admin API, Grafana + Prometheus | 5–8 | Theo master-plan |
| AI-01, SCORE-01, VECTOR-01, RECOMMEND-01 | Dịch vụ AI | 9–13 | Tốt nên có (**chưa có commit của TM2 trong `ai-svc`**) |

### 1.2 Đóng góp thực tế (từ git log, tác giả `Nguyen Thanh`)

| Repo | Số commit | Nội dung chính |
|:--|:--:|:--|
| `job-platform-job-svc` | ~49 | CRUD Job + Company (chống race điều kiện unique tên công ty), Category seed, DevAuthMiddleware, Kafka publisher `job-events` + circuit-breaker fallback sang HTTP sync, trạng thái `Pending/Rejected` + Admin duyệt/từ chối tin + Outbox publisher, endpoint nội bộ `/api/internal/stats`, `/metrics` Prometheus |
| `job-platform-search-svc` | ~31 | Elasticsearch: query DSL, suggest, HTTP index / bulk-index / delete, analyzer tiếng Việt (ICU) + lọc kỹ năng, script reindex, chặn phân trang sâu (`from > 500` → 400), benchmark PERF-02 < 200ms, Kafka consumer `job-events` (idempotent, bỏ qua message lỗi), xóa job không còn searchable khỏi index, `/metrics` |
| `job-platform-crawler` | ~29 | Scrapy spider `vieclam`, pipeline làm sạch/dedup/PostgreSQL/Elasticsearch, BlockDetectionMiddleware + fallback seed `seed/jobs.json` (550 bản ghi), crawl-500 + verify-500, Dockerfile, unit test |
| `job-platform-profile-svc` | ~25 | Toàn bộ service: Profile/Skill/Experience/Education CRUD, mã hóa PII AES-256-GCM, Swagger, DevAuth, test unit + integration, Dockerfile, `/metrics` |
| `job-platform-notif-svc` | ~24 | Scaffold service, consume `application-events` → gửi email, NotificationLog idempotent, endpoint lịch sử có token, email báo nhà tuyển dụng khi tin được duyệt/từ chối, `/metrics` |
| `job-platform-infra` | ~15 | Image ES custom có plugin `analysis-icu`, đổi sang `apache/kafka`, Redis revocation store, Grafana + Prometheus + dashboards, **`docker-compose.full.yml`** |
| `job-platform-app-svc` | ~14 | Lấy JobTitle từ job-svc trước khi publish event, `/api/internal/stats`, `/metrics` |
| `job-platform-auth-svc` | ~14 | Admin quản lý user + audit log, thu hồi token, thống kê dashboard admin, `/metrics` |
| `job-platform-gateway` | ~10 | Bảo vệ route admin bằng policy Admin, enforce thu hồi access token, `/metrics` |
| `job-platform-shared` | ~10 | SharedKernel 0.2.0: contract sự kiện Kafka, KafkaProducer/ConsumerService, SASL/TLS, 30 test xUnit |
| `job-platform-docs` | 5 | SRS phần AI (SCREEN-01, CHG-008 self-hosted model) |

> ⚠️ **Lưu ý nhánh:** hiện nhiều repo local đang ở nhánh `feat/prometheus-metrics` và **chậm hơn `origin/main`** (job-svc chậm 8 commit, auth/gateway 7, app/notif 3...). Một số tính năng (vd. `/api/internal/stats`, email duyệt tin) **chỉ có trên `main`**. Trước khi build, chạy:
> ```powershell
> # tại D:\Code\pbl6
> .\pull_all.bat          # hoặc với từng repo:
> git -C job-platform-job-svc checkout main; git -C job-platform-job-svc pull
> ```

---

## 2. YÊU CẦU CHUẨN BỊ

- **Docker Desktop** (WSL 2 backend), cấp tối thiểu **6 GB RAM** cho WSL (`%USERPROFILE%\.wslconfig` → `memory=6GB`, rồi `wsl --shutdown`). Xem thêm `HUONG_DAN_CHAY_DOCKER_DESKTOP.md`.
- Các cổng phải trống: `5000–5006, 5173, 5432, 6379, 9200, 9092, 9093, 8080, 1025, 8025, 9090, 3001`.
  ```powershell
  Get-NetTCPConnection -State Listen | Where-Object LocalPort -in 5000,5001,5002,5003,5004,5005,5006,5173,5432,6379,9200,9092,8080,8025,9090,3001
  ```
- File môi trường `job-platform-infra/envs/.env.dev` (đã có; nếu thiếu: `powershell -ExecutionPolicy Bypass -File job-platform-infra\scripts\sync-env.ps1 dev`).
- (Tùy chọn, để chạy crawler/test ngoài Docker) Python 3.12+, .NET 10 SDK, `mise`.

---

## 3. CHẠY TOÀN BỘ HỆ THỐNG BẰNG DOCKER

Dùng file **`docker-compose.full.yml`** (TM2 viết) — build *tất cả* microservice từ source local, kèm hạ tầng và monitoring.

```powershell
cd D:\Code\pbl6\job-platform-infra

# Lần đầu (hoặc khi code thay đổi): build + chạy nền
docker compose -f docker-compose.full.yml up -d --build

# Theo dõi trạng thái (đợi tất cả "healthy", khoảng 2–5 phút lần đầu)
docker compose -f docker-compose.full.yml ps

# Xem log 1 service
docker compose -f docker-compose.full.yml logs -f job
docker compose -f docker-compose.full.yml logs -f search

# Rebuild riêng 1 service sau khi sửa code
docker compose -f docker-compose.full.yml up -d --build search

# Dừng (giữ dữ liệu) / dừng và xóa sạch dữ liệu
docker compose -f docker-compose.full.yml down
docker compose -f docker-compose.full.yml down -v
```

> Chỉ cần hạ tầng (Postgres, Redis, ES, Kafka, MailHog) để chạy service bằng `dotnet run`? Dùng `docker compose up -d` (file `docker-compose.yml` mặc định) hoặc `docker-start.bat`.

### 3.1 Bảng địa chỉ truy cập

| Thành phần | URL | Ghi chú |
|:--|:--|:--|
| API Gateway | http://localhost:5000/health | Cần JWT cho route bảo vệ |
| Auth Service — Swagger | http://localhost:5001/swagger | Bearer JWT |
| **Job Service — Swagger** | http://localhost:5002/swagger | Header `X-User-Id`, `X-User-Role` |
| **Search Service — Swagger** | http://localhost:5003/swagger | Public |
| Application Service — Swagger | http://localhost:5004/swagger | Header `X-User-Id`, `X-User-Role` |
| **Profile Service — Swagger** | http://localhost:5005/swagger | Header `X-User-Id`, `X-User-Role` |
| **Notification Service — Swagger** | http://localhost:5006/swagger | `X-Internal-Token` (nếu cấu hình) |
| Web | http://localhost:5173 | |
| Kafka UI | http://localhost:8080 | Xem topic `job-events`, `application-events` |
| MailHog | http://localhost:8025 | Hộp thư giả lập |
| Elasticsearch | http://localhost:9200 | Index `jobs` |
| Prometheus | http://localhost:9090/targets | |
| Grafana | http://localhost:3001 | `admin` / `admin` |
| Metrics từng service | http://localhost:500X/metrics | Prometheus format |

Kiểm tra nhanh tất cả health:
```powershell
5000..5006 | ForEach-Object { "{0}: {1}" -f $_, (curl.exe -s "http://localhost:$_/health") }
```

---

## 4. CÁCH XÁC THỰC KHI DÙNG SWAGGER

Compose chạy service với `ASPNETCORE_ENVIRONMENT=Development` → Swagger bật và **DevAuthMiddleware** thay cho JWT. Có 2 cách test:

### Cách A — Gọi thẳng service (khuyên dùng cho Swagger)
1. Mở Swagger của service (vd. http://localhost:5002/swagger).
2. Nhấn **Authorize** 🔒, điền:
   - `X-User-Id`: một UUID bất kỳ, vd. `11111111-1111-1111-1111-111111111111`
   - `X-User-Role`: `Recruiter` | `User` | `Admin` (phân biệt hoa thường)
3. **Authorize → Close**, rồi "Try it out".

UUID gợi ý dùng xuyên suốt:

| Vai trò | X-User-Id | X-User-Role |
|:--|:--|:--|
| Nhà tuyển dụng | `11111111-1111-1111-1111-111111111111` | `Recruiter` |
| Ứng viên | `22222222-2222-2222-2222-222222222222` | `User` |
| Quản trị | `33333333-3333-3333-3333-333333333333` | `Admin` |

> Log sẽ có cảnh báo *"X-User-Id header received without gateway trust header"* — bình thường trong Development.

### Cách B — Đi qua Gateway với JWT thật (kiểm thử end-to-end)
1. Swagger Auth http://localhost:5001/swagger → `POST /api/auth/register`:
   ```json
   { "email": "recruiter1@test.com", "password": "Password@123", "fullName": "Recruiter One", "role": "Recruiter", "companyName": "TM2 Test Co" }
   ```
2. `POST /api/auth/login` → copy `accessToken`.
3. Gọi qua gateway `http://localhost:5000/api/...` với header `Authorization: Bearer <accessToken>`. Gateway tự xóa `X-User-*` do client gửi và chèn lại từ JWT (chống giả mạo).
   ```powershell
   $t = "<accessToken>"
   curl.exe -s -H "Authorization: Bearer $t" http://localhost:5000/api/jobs/recruiter
   ```

---

## 5. KỊCH BẢN KIỂM THỬ THEO TÍNH NĂNG

> Ký hiệu: ✅ = kết quả mong đợi.

### 5.1 Job Service — JOB-01 (http://localhost:5002/swagger)

**Bước 1. Danh mục (public)** — `GET /api/categories`
✅ 200, danh sách seed: IT, Tài chính, Marketing, Y tế, Giáo dục, Kỹ thuật, Bán hàng, Khách sạn, Khác. Ghi lại 1 `id` làm `categoryId`.

**Bước 2. Tạo công ty** (Role `Recruiter`) — `POST /api/companies`
```json
{
  "name": "TM2 Software JSC",
  "taxCode": "0312345678",
  "website": "https://tm2.example.com",
  "description": "Công ty kiểm thử",
  "address": "Đà Nẵng",
  "industry": "IT",
  "size": "50-100"
}
```
✅ 201 + `id` (ghi lại `companyId`).
- Gửi lại cùng `name` (kể cả khác hoa/thường, vd. `tm2 software jsc`) → ✅ **409 Conflict**.
- Role `User` → ✅ 403. Không có `X-User-Id` → ✅ 401.
- `GET /api/companies`, `GET /api/companies/{id}`, `PUT /api/companies/{id}` (chỉ người tạo).

**Bước 3. Tạo tin tuyển dụng** (Role `Recruiter`) — `POST /api/jobs`
```json
{
  "title": "Lập trình viên .NET Backend",
  "description": "Phát triển microservices với ASP.NET Core, Kafka, Elasticsearch",
  "companyId": "<companyId>",
  "location": "Đà Nẵng",
  "salaryMin": 15000000,
  "salaryMax": 25000000,
  "salaryCurrency": "VND",
  "categoryId": "<categoryId>",
  "requirements": "C#, .NET, PostgreSQL, Docker",
  "benefits": "Lương tháng 13, bảo hiểm",
  "employmentType": "FullTime",
  "experienceLevel": "Junior"
}
```
✅ 201 + `id` (`jobId`). `companyId` không tồn tại → ✅ 400 `"Company not found."`.
Mặc định status = `Active`; nếu bật `FEATURE_ADMIN_APPROVAL=true` thì status = `Pending` (xem 5.6).

**Bước 4. Các thao tác còn lại**

| Endpoint | Kiểm tra | ✅ Mong đợi |
|:--|:--|:--|
| `GET /api/jobs/{id}` | không cần header | 200, có `companyName`, `categoryName` |
| `GET /api/jobs/recruiter?status=Active&page=0&size=10` | Role Recruiter | Chỉ thấy tin của mình, có phân trang |
| `PUT /api/jobs/{id}` | đổi `X-User-Id` sang UUID khác | 403 (chỉ chủ sở hữu) |
| `PUT /api/jobs/{id}` | chủ sở hữu, đổi `title` | 200, `updatedAt` thay đổi |
| `DELETE /api/jobs/{id}` | chủ sở hữu | 200; sau đó `GET /api/jobs/{id}` → 404 (xóa mềm, bản ghi vẫn còn trong DB) |

Kiểm tra xóa mềm trong DB:
```powershell
docker exec -it job-platform-postgres psql -U postgres -d job_platform_job -c "SELECT \"Id\",\"Title\",\"Status\" FROM \"Jobs\" ORDER BY \"CreatedAt\" DESC LIMIT 5;"
```
*(nếu tên bảng/cột khác, liệt kê bằng `\dt` và `\d "Jobs"`)*

### 5.2 Đồng bộ Job → Kafka → Elasticsearch (SEARCH-01-01, tuần 5–8)

Sau khi tạo/sửa/xóa job ở 5.1:
1. **Kafka UI** http://localhost:8080 → Topics → `job-events` → Messages: ✅ có message `JobCreated/JobUpdated/JobDeleted`, **key = JobId**.
2. Consumer group của search-svc: ✅ lag về 0.
3. Elasticsearch:
   ```powershell
   curl.exe -s "http://localhost:9200/jobs/_doc/<jobId>?pretty"
   curl.exe -s "http://localhost:9200/jobs/_count?pretty"
   ```
   ✅ Tạo → có document; Xóa → document biến mất (404).
4. **Circuit-breaker:** `docker stop job-platform-kafka`, tạo 1 job mới → ✅ API vẫn trả 201 (fallback HTTP sync, log cảnh báo); `docker start job-platform-kafka` → publisher tự phục hồi.

> ℹ️ **Đã sửa (2026-11-04, commit `9038f78` trên `feature/full-dev-compose`):** `docker-compose.full.yml` trước đây đặt `SEARCH_SYNC_URL: http://search:5003/api/search/sync`. Vì job-svc tự nối thêm `/api/search/index`, đường đồng bộ dự phòng qua HTTP bị 404. Giờ biến này đã đổi thành `http://search:5003` (khớp với `docker-compose.prod.yml`). Nếu container `job` đã chạy từ trước, cần tạo lại: `docker compose -f docker-compose.full.yml up -d job`.

### 5.3 Search Service — SEARCH-01 & ADV-01 (http://localhost:5003/swagger)

Nạp dữ liệu trước (chọn 1):
- Tạo vài job qua 5.1 (tự đồng bộ), **hoặc**
- Nạp 550 tin seed từ crawler (xem 5.5), **hoặc**
- `POST /api/search/bulk-index` (nội bộ; nếu đặt `SEARCH_INDEX_TOKEN` thì thêm header `X-Internal-Token`).

| # | Request `GET /api/search/jobs?...` | ✅ Mong đợi |
|:--|:--|:--|
| 1 | `q=lap trinh` | Khớp cả "Lập trình" (ICU folding bỏ dấu), có điểm liên quan |
| 2 | `q=.NET&location=Đà Nẵng` | Chỉ tin ở Đà Nẵng; khớp một phần địa điểm |
| 3 | `minSalary=10000000&maxSalary=20000000` | Tin có khoảng lương giao nhau |
| 4 | `skills=C#,Docker` | Lọc theo kỹ năng |
| 5 | `employmentType=FullTime&experienceLevel=Junior&category=IT` | Lọc từ khóa chính xác |
| 6 | `sortBy=created_at_desc` / `created_at_asc` / `salary_desc` / `salary_asc` | Sắp xếp đúng (bỏ trống = theo độ liên quan khi có `q`) |
| 7 | `page=0&size=5` | Có `total`, `totalPages`, đúng 5 item |
| 8 | `q=xyzkhongtontai` | **200** + `items: []` + thông báo không tìm thấy |
| 9 | `page=-1` | **400** "Invalid pagination" |
| 10 | `size=0` hoặc `size=101` | **400** |
| 11 | `page=200&size=5` (from > 500) | **400** — chặn deep pagination |

- `GET /api/search/suggest?q=lap` → ✅ mảng gợi ý; thiếu `q` → 400.
- Gọi lại cùng truy vấn: ✅ nhanh hơn (Redis cache). Kiểm tra: `docker exec -it job-platform-redis redis-cli KEYS "*"`.
- Kiểm tra analyzer tiếng Việt trực tiếp:
  ```powershell
  curl.exe -s -X POST "http://localhost:9200/jobs/_analyze?pretty" -H "Content-Type: application/json" -d '{\"field\":\"title\",\"text\":\"Lập trình viên Hà Nội\"}'
  ```
- **Benchmark PERF-02 (< 200ms):** xem hướng dẫn trong `job-platform-search-svc` (script `benchmark.py`, README mục PERF-02).

### 5.4 Profile Service — PROFILE-01 (http://localhost:5005/swagger)

Authorize với `X-User-Id = 22222222-...`, `X-User-Role = User`.

| Bước | Endpoint | Body mẫu | ✅ Mong đợi |
|:--|:--|:--|:--|
| 1 | `PUT /api/profiles/me` | `{"fullName":"Nguyễn Văn Test","headline":"Backend Dev","summary":"3 năm .NET","phone":"0905123456","address":"Đà Nẵng","dateOfBirth":"2002-05-10"}` | 200, tự tạo hồ sơ nếu chưa có |
| 2 | `POST /api/profiles/skills` | `{"name":"C#","proficiency":4,"yearsOfExperience":3}` | 201 + id |
| 3 | `POST /api/profiles/skills` | `{"name":"Go","proficiency":6,"yearsOfExperience":1}` | **400** (proficiency phải 1–5) |
| 4 | `POST /api/profiles/experiences` | `{"company":"FPT","title":"Intern","startDate":"2024-06-01","endDate":"2024-12-01","isCurrent":false,"description":"..."}` | 201 |
| 5 | `POST /api/profiles/educations` | `{"institution":"ĐH Bách khoa Đà Nẵng","degree":"Kỹ sư","field":"CNTT","startDate":"2020-09-01","endDate":"2025-06-30","grade":"Giỏi"}` | 201 |
| 6 | `PUT/DELETE /api/profiles/experiences/{id}`, `/educations/{id}`, `DELETE /skills/{id}` | — | 200/204; đổi `X-User-Id` khác → 403/404 |
| 7 | `GET /api/profiles/me` | — | 200, đầy đủ skills/experiences/educations |
| 8 | `GET /api/profiles/{userId}` (public) | — | 200, **không có** `phone`, `address`, `dateOfBirth` |
| 9 | Bỏ header `X-User-Id` khi gọi `/me` | — | **401** |

Kiểm tra **mã hóa PII AES-256-GCM** (SEC-08) — dữ liệu nhạy cảm trong DB phải là chuỗi mã hóa, không phải plain text:
```powershell
docker exec -it job-platform-postgres psql -U postgres -d job_platform_profile -c "\dt"
docker exec -it job-platform-postgres psql -U postgres -d job_platform_profile -c "SELECT * FROM profiles LIMIT 3;"
```
✅ Cột phone/address không đọc được bằng mắt.

### 5.5 Crawler — CRAWL-01

**Cách 1 — chạy local bằng Python (khuyên dùng)**, khi Postgres + ES trong Docker đang chạy:
```powershell
cd D:\Code\pbl6\job-platform-crawler
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item ..\job-platform-infra\envs\.env.dev .env      # trỏ localhost:5432 / localhost:9200

python scripts/check_connectivity.py                     # ✅ kết nối PG + ES OK
scrapy check vieclam                                     # ✅ contracts pass
scrapy crawl vieclam -s MAX_PAGES=10 -s LOG_LEVEL=INFO   # dev ~100 tin
scrapy crawl vieclam -s MAX_PAGES=50 -s LOG_LEVEL=INFO   # mục tiêu 500+ tin
python scripts/verify_500.py                             # ✅ >= 500 tin không trùng trong PG và ES
```
(Có `mise`: `mise run crawl-500`, `mise run verify-500`, `mise run seed`, `mise run verify`.)

**Cách 2 — chạy bằng Docker** (Dockerfile có sẵn), dùng network của compose:
```powershell
cd D:\Code\pbl6\job-platform-crawler
docker build -t job-platform-crawler .
docker run --rm --network job-platform-full_job-platform --env-file ..\job-platform-infra\envs\.env.dev `
  -e DATABASE_URL="Host=postgres;Port=5432;Database=job_platform;Username=postgres;Password=123456" `
  -e ELASTICSEARCH_URL=http://elasticsearch:9200 job-platform-crawler
```
*(Kiểm tra tên network bằng `docker network ls`; tên biến môi trường chính xác xem `crawler/settings.py` / README.)*

**Kiểm thử fallback (CRAWL-01-07):** nếu site trả 403/429 hoặc parse lỗi > 5 lần liên tiếp → spider dừng và nạp `seed/jobs.json` (550 bản ghi). Chạy trực tiếp: `python scripts/seed_loader.py`.
✅ Sau đó `curl.exe -s http://localhost:9200/jobs/_count` ≥ 500 và tìm được qua Search Swagger.

**Unit test:** `pytest tests/ -v` • lint: `ruff check crawler/ scripts/ tests/`.

### 5.6 Admin duyệt tin + Outbox + Email (tuần 7–8)

1. Bật cờ duyệt tin: thêm vào service `job` trong `docker-compose.full.yml` → `FEATURE_ADMIN_APPROVAL: "true"`; và service `notif` → `NOTIF_JOB_EVENTS_ENABLED: "true"`. Rồi `docker compose -f docker-compose.full.yml up -d job notif`.
2. Recruiter tạo job (5.1) → ✅ status `Pending`, **chưa** xuất hiện trong search.
3. Job Swagger, Authorize `X-User-Role = Admin`:
   - `GET /api/admin/jobs?status=Pending` → ✅ thấy tin vừa tạo.
   - `POST /api/admin/jobs/{id}/approve` → ✅ status `Active`; job xuất hiện trong ES.
   - Tin khác: `POST /api/admin/jobs/{id}/reject` body `{"reason":"Thiếu mô tả lương"}` → ✅ `Rejected`, không có trong ES.
   - Gọi bằng role `Recruiter` → ✅ 403.
4. Kafka UI: ✅ sự kiện approve/reject được Outbox publish lên `job-events`.
5. **MailHog** http://localhost:8025: ✅ email báo duyệt/từ chối gửi tới nhà tuyển dụng (nếu không có email thật, notif dùng `NOTIF_DEFAULT_RECIPIENT`).
6. Notif Swagger http://localhost:5006/swagger → `GET /api/notifications/history` (header `X-Internal-Token` nếu có đặt `NOTIF_HISTORY_TOKEN`) → ✅ có log, gửi lại cùng sự kiện không bị gửi trùng (idempotent).

### 5.7 Luồng ứng tuyển → Email (application-events)

1. App Swagger http://localhost:5004/swagger, Authorize `User` → `POST /api/applications` (form-data: `jobId`, `coverLetter`, file CV PDF).
2. ✅ Kafka `application-events` có message chứa **JobTitle** (app-svc gọi job-svc lấy tiêu đề — commit B-10).
3. Recruiter `PUT /api/applications/{id}/status` `{"status":"reviewed"}` → ✅ MailHog nhận email đổi trạng thái.

### 5.8 Admin user & thống kê (auth-svc, gateway)

1. Đăng nhập tài khoản Admin (tài khoản seed/được set role Admin trong DB) → lấy JWT.
2. Qua gateway: `GET http://localhost:5000/api/admin/users`, `PATCH /api/admin/users/{id}/deactivate|activate`, `GET /api/admin/stats`.
   ✅ Token không phải Admin → 403. ✅ User bị deactivate → token cũ bị thu hồi (401) nhờ Redis revocation store.
3. `/api/admin/stats` tổng hợp từ `job-svc` và `app-svc` qua `GET /api/internal/stats` (header `Authorization: Bearer <INTERNAL_SERVICE_TOKEN>`; thiếu token → 401).

### 5.9 Monitoring — Prometheus + Grafana

- Mỗi service: `curl.exe -s http://localhost:5002/metrics | Select-Object -First 20` → ✅ có metric `http_server_request_duration_seconds`, `dotnet_*`.
- Prometheus http://localhost:9090/targets → ✅ các target `UP`.
- Grafana http://localhost:3001 (`admin/admin`) → Dashboards → ✅ biểu đồ request rate, latency, runtime.
- Production tắt `/metrics` trừ khi `METRICS_ENABLED=true`.

---

## 6. CHẠY UNIT/INTEGRATION TEST (ngoài Docker)

```powershell
# .NET services (cần .NET 10 SDK)
cd D:\Code\pbl6\job-platform-job-svc;     dotnet test
cd D:\Code\pbl6\job-platform-search-svc;  dotnet test
cd D:\Code\pbl6\job-platform-profile-svc; dotnet test   # integration test cần Postgres đang chạy (localhost:5432)
cd D:\Code\pbl6\job-platform-notif-svc;   dotnet test -c Release
cd D:\Code\pbl6\job-platform-shared;      dotnet test

# Crawler
cd D:\Code\pbl6\job-platform-crawler;     pytest tests/ -v
```

---

## 7. XỬ LÝ SỰ CỐ THƯỜNG GẶP

| Triệu chứng | Nguyên nhân / Cách xử lý |
|:--|:--|
| `/swagger` trả 404 | Service không chạy ở Development. Kiểm tra `ASPNETCORE_ENVIRONMENT=Development` trong compose. |
| API trả 401 trong Swagger | Chưa Authorize `X-User-Id` (phải là UUID hợp lệ). |
| API trả 403 | Sai `X-User-Role` (phân biệt hoa thường: `Recruiter`, `Admin`) hoặc không phải chủ sở hữu. |
| Job tạo xong nhưng search không thấy | Kiểm tra log `search` (consumer Kafka), topic `job-events` trong Kafka UI; status phải `Active`; kiểm tra `SEARCH_SYNC_URL=http://search:5003` (mục 5.2). |
| Elasticsearch exit 137 / không healthy | Thiếu RAM — tăng `memory` trong `.wslconfig`. |
| ES báo thiếu analyzer `icu_*` | Phải dùng image custom: `docker compose -f docker-compose.full.yml build elasticsearch`. Nếu index cũ tạo trước khi có analyzer → chạy script `recreate_index.py` trong search-svc. |
| Kafka không lên | Xóa volume cũ: `docker compose -f docker-compose.full.yml down -v` (mất dữ liệu). |
| Profile-svc không khởi động | Thiếu `PROFILE_ENCRYPTION_KEY` (64 ký tự hex) ngoài Development. |
| Không thấy email | Mở MailHog http://localhost:8025; kiểm tra `SMTP_HOST=mailhog`, cờ `NOTIF_JOB_EVENTS_ENABLED`. |
| Thiếu endpoint so với tài liệu | Repo local đang ở nhánh cũ — `git checkout main && git pull` rồi `up -d --build`. |
| Cổng bị chiếm | `netstat -ano \| findstr :5432` → tắt Postgres/Redis cài sẵn trên Windows. |

---

## 8. CHECKLIST NGHIỆM THU TM2

- [ ] Toàn bộ container `healthy` (`docker compose -f docker-compose.full.yml ps`)
- [ ] JOB-01: CRUD job/company/category, phân quyền chủ sở hữu, xóa mềm
- [ ] SEARCH-01: từ khóa, địa điểm, phân trang, kết quả rỗng trả 200
- [ ] ADV-01: lọc lương/kỹ năng/loại hình/kinh nghiệm, tiếng Việt không dấu, sắp xếp, chặn deep pagination
- [ ] Đồng bộ Job → Kafka → ES (tạo/sửa/xóa), circuit-breaker fallback
- [ ] PROFILE-01: CRUD hồ sơ + kỹ năng/kinh nghiệm/học vấn, validate, hồ sơ public ẩn PII, PII mã hóa trong DB
- [ ] CRAWL-01: ≥ 500 tin không trùng trong PG + ES, fallback seed hoạt động
- [ ] Admin duyệt/từ chối tin + Outbox + email MailHog
- [ ] Notification từ `application-events`, idempotent
- [ ] Admin user/stats qua gateway, thu hồi token
- [ ] `/metrics` + Prometheus targets UP + Grafana dashboards
- [ ] Unit test các repo pass
