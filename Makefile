# Makefile shim — one-command sync
# Usage: make sync-env  OR  make sync-env-prod
# OR from parent ~/projects/personal/job-platform: make -C job-platform-infra sync-env

ORG ?= dut-pbl6-2026
ifeq ($(ORG),dut-pbl6-2026)
else
  $(error ORG must be dut-pbl6-2026)
endif

sync-env:
	@./scripts/sync-env.sh dev

sync-env-prod:
	@./scripts/sync-env.sh prod

verify:
	@ls -1 ../job-platform-*/.env 2>/dev/null | wc -l; echo " repos have .env (expected 14)"
	@grep -qi techsoft envs/.env.dev 2>/dev/null && echo "ERROR techsoft in env" && exit 1 || echo "no techsoft in env — ok"

help:
	@echo "Targets: sync-env, sync-env-prod, verify"
