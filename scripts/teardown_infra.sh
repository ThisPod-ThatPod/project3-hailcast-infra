#!/bin/bash
# =============================================================
# 파일위치 : project3-hailcast-infra/scripts/teardown_infra.sh
# 역할     : infra 레포 terraform destroy 진입점 (ops 위임 대상)
# 호출     : ops/scripts/teardown.sh 가 manifest 다음(2번째)으로 부른다.
# 전제     : manifest teardown 이 먼저 끝나 ALB·ENI 가 없어야 VPC destroy 가 막히지 않는다.
# 안전 계약 :
#   - 실제 destroy 는 CONFIRM=yes 일 때만.  (ops 가 destroy-all 시 주입)
#   - ALB 가 살아있으면 실제 destroy 는 막힌다. 알고도 강행하려면 FORCE=yes (사람만 지정, 자동주입 금지).
#   - CONFIRM 없으면 plan -destroy(미리보기)만 → 실수 실행 안전.
# 커스터마이징(★) : ENV_DIR(환경 경로) · RDS 사전 스냅샷 정책
# =============================================================
set -euo pipefail

# 스크립트 자기 위치로 레포 루트를 잡는다 → 어디서 호출하든(ops 경유 포함) 동작한다
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIRM="${CONFIRM:-}"                    # 진짜 지운다
FORCE="${FORCE:-}"                        # ALB 경고를 무시한다 (뜻을 분리)
ENV_DIR="${ENV_DIR:-envs/dev}"            # ★ 환경 경로
AWS_REGION="${AWS_REGION:-ap-northeast-2}"

TARGET_DIR="$REPO_ROOT/$ENV_DIR"
[ -d "$TARGET_DIR" ] || { echo "[infra] $TARGET_DIR 없음"; exit 1; }

echo "[infra] terraform destroy 준비 ($TARGET_DIR)"

# ── ALB 잔여 가드 : '조회 실패' 와 'ALB 없음' 을 구분한다 ──
if ! LEFT_ALB=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
        --query "LoadBalancers[?contains(LoadBalancerName,'k8s')].LoadBalancerName" \
        --output text); then
    echo "[infra] ALB 조회 실패 (자격증명·권한·리전 확인). 안전을 위해 중단합니다."
    exit 1
fi

if [ -n "$LEFT_ALB" ]; then
    echo "[infra] K8s 가 만든 ALB 가 아직 있습니다: $LEFT_ALB"
    echo "        manifest teardown 을 먼저 끝내세요. ENI 가 남아 VPC destroy 가 막힙니다."
    # 막아야 할 것은 '진짜 destroy' 뿐이다. 미리보기(plan -destroy)는 해가 없으니 통과시킨다.
    if [ "$CONFIRM" = "yes" ] && [ "$FORCE" != "yes" ]; then
        echo "[infra] 실제 destroy 를 중단합니다. (경고를 알고도 강행하려면 FORCE=yes)"
        exit 1
    fi
fi

cd "$TARGET_DIR"
terraform init -input=false               # 새 clone 에서도 destroy 가 되도록 (멱등)

# ── ★ (선택) RDS 데이터 보존이 필요하면 destroy 전에 수동 스냅샷 ──
#   RDS 는 skip_final_snapshot=true 라 destroy 시 자동 스냅샷이 없다(dev 데모 기본값).
#   데이터를 남겨야 하는 상황이면 아래 주석을 해제해 먼저 스냅샷을 뜬다.
# aws rds create-db-snapshot \
#     --db-instance-identifier hailcast-dev-rds-postgres \
#     --db-snapshot-identifier hailcast-dev-final-$(date +%Y%m%d) \
#     --region "$AWS_REGION"

if [ "$CONFIRM" = "yes" ]; then
    echo "  \$ terraform destroy -auto-approve"
    terraform destroy -auto-approve       # 실패하면 set -e 가 비정상 종료시킨다
    echo "[infra] destroy 완료. 잔여 리소스 확인(ENI·EBS·EIP·NAT·로그그룹)."
else
    echo "    (미실행 - 검토용. 실제 삭제는 CONFIRM=yes)"
    terraform plan -destroy
    echo "[infra] 미리보기만 했습니다. 실제로 지우려면 CONFIRM=yes 로 다시 실행하세요."
fi