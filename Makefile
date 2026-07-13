# =============================================================
# 파일 위치 : project3-hailcast-infra/Makefile
# 소유      : 그룹 A (유현상·이미선)
# 역할      : ops 의 make -C 위임을 받는 진입점(init/fmt/plan/apply/destroy).
# 사용      : 이 레포에서  make plan   /  ops 에서  make infra-plan
# =============================================================

ENV_DIR ?= envs/dev

.PHONY: help init fmt plan apply destroy teardown
help:    ## 명령 목록
	@echo "  make init | fmt | plan | apply | destroy   (ENV_DIR=$(ENV_DIR))"

init:    ## terraform init
	cd $(ENV_DIR) && terraform init

fmt:     ## terraform fmt (전체)
	terraform fmt -recursive

plan:    ## terraform plan
	cd $(ENV_DIR) && terraform plan

apply:   ## terraform apply (비용 시작 — 팀 합의 후)
	cd $(ENV_DIR) && terraform apply

# destroy 는 안전 가드가 든 teardown 스크립트로 위임(ALB 잔여 확인 → terraform destroy)
destroy: teardown
teardown: ## AWS 자원 정리 (scripts/teardown_infra.sh)
	@chmod +x scripts/teardown_infra.sh && bash scripts/teardown_infra.sh