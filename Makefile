# =============================================================
# 파일 위치 : project3-hailcast-infra/Makefile
# 소유      : 그룹 A (유현상·이미선)
# 역할      : ops 의 make -C 위임을 받는 진입점(init/fmt/plan/apply/destroy).
# 사용      : 이 레포에서  make plan   /  ops 에서  make infra-plan
# =============================================================

ENV_DIR ?= envs/dev

# 잠금 대기 — 다른 사람(또는 CI)이 state 를 잠근 중이면 즉시 죽지 않고 기다린다.
TF_LOCK ?= -lock-timeout=5m

.PHONY: help init fmt validate plan apply destroy teardown
help:    ## 명령 목록
	@echo "  make init | fmt | validate | plan | apply | destroy   (ENV_DIR=$(ENV_DIR))"

init:    ## terraform init
	cd $(ENV_DIR) && terraform init -input=false

fmt:     ## terraform fmt (전체)
	terraform fmt -recursive

validate: ## terraform validate (자격증명 불필요)
	cd $(ENV_DIR) && terraform validate

plan:    ## terraform plan
	cd $(ENV_DIR) && terraform plan -input=false $(TF_LOCK)

# ⚠️ apply 는 일부러 -auto-approve 를 안 붙인다. 사람이 yes 를 쳐야 한다(비용이 시작된다).
#    CI 는 이 타깃을 쓰지 않는다 — .github/workflows/terraform.yml 이 terraform 을 직접 부르고,
#    승인은 GitHub environment(infra-apply)가 job 시작 전에 막는다.
apply:   ## terraform apply (비용 시작 — 사람이 yes 를 쳐야 한다)
	cd $(ENV_DIR) && terraform apply -input=false $(TF_LOCK)

# destroy 는 안전 가드가 든 teardown 스크립트로 위임(ALB 잔여 확인 → terraform destroy)
destroy: teardown
teardown: ## AWS 자원 정리 (scripts/teardown_infra.sh)
	@chmod +x scripts/teardown_infra.sh && bash scripts/teardown_infra.sh