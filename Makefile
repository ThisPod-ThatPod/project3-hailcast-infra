# =============================================================
# 파일 위치 : project3-hailcast-infra/Makefile
# 소유      : 그룹 A (유현상·이미선)
# 역할      : ops 의 make -C 위임을 받는 진입점(init/fmt/plan/apply/destroy).
# 사용      : 이 레포에서  make plan   /  ops 에서  make infra-plan
# =============================================================

ENV_DIR ?= envs/dev

# 잠금 대기 — 다른 사람(또는 CI)이 state 를 잠근 중이면 즉시 죽지 않고 기다린다.
TF_LOCK ?= -lock-timeout=5m

# teardown 게이트값 — 명령줄(make teardown CUR_HANDLING=keep)과 환경변수(CUR_HANDLING=keep make teardown)
# 둘 다 동작하도록 빈 기본값으로 선언해두고, 레시피에서 명시적으로 $(...)를 스크립트에 넘긴다.
CONFIRM ?=
FORCE ?=
CUR_HANDLING ?=

.PHONY: help init fmt validate plan apply destroy teardown
help:    ## 명령 목록
	@echo "  make init | fmt | validate | plan | apply   (ENV_DIR=$(ENV_DIR))"
	@echo "  make destroy                                 (CONFIRM 없으면 plan -destroy 미리보기만)"
	@echo "  make destroy CUR_HANDLING=keep|drop CONFIRM=yes FORCE=yes   (실제 삭제)"

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

# destroy 는 안전 가드가 든 teardown 스크립트로 위임
# (CUR 버킷 → ALB → Karpenter 노드 3중 가드 → terraform destroy)
destroy: teardown
teardown: ## AWS 자원 정리 (scripts/teardown_infra.sh) — 게이트값은 위 help 참고
	@chmod +x scripts/teardown_infra.sh
	@CONFIRM=$(CONFIRM) FORCE=$(FORCE) CUR_HANDLING=$(CUR_HANDLING) ENV_DIR=$(ENV_DIR) \
		bash scripts/teardown_infra.sh