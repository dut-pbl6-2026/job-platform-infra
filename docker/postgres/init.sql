-- job-platform-infra/docker/postgres/init.sql — PBL6-11 init 6 PG (MUST 5 + AI NICE) per SRS 8 DB-per-service
-- Runs once on first `docker compose up` volume init (pg_data empty).
-- Idempotent via SELECT from pg_database.
SELECT 'CREATE DATABASE job_platform_auth' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='job_platform_auth')\gexec
SELECT 'CREATE DATABASE job_platform_job' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='job_platform_job')\gexec
SELECT 'CREATE DATABASE job_platform_app' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='job_platform_app')\gexec
SELECT 'CREATE DATABASE job_platform_profile' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='job_platform_profile')\gexec
SELECT 'CREATE DATABASE job_platform_notif' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='job_platform_notif')\gexec
SELECT 'CREATE DATABASE job_platform_ai' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='job_platform_ai')\gexec
-- job_platform already created via POSTGRES_DB; ensure extensions
\c job_platform
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
\c job_platform_auth
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
\c job_platform_job
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
\c job_platform_app
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
\c job_platform_profile
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
\c job_platform_notif
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
\c job_platform_ai
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
