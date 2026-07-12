#!/bin/bash
# =============================================================
# 파일 위치 : project3-hailcast-infra/scripts/teardown_infra.sh
# 소유      : 그룹 A (유현상·이미선)
# 역할      : terraform destroy 로 AWS 자원(EKS·노드·RDS·SQS·S3·NAT·VPC…)을 내린다.
# 호출      : ops 의 teardown.sh 가 manifest 다음(2번째)에 부른다.
# 전제      : manifest teardown 이 먼저 끝나 ALB·ENI 가 없어야 VPC destroy 가 막히지 않는다.
# 커스터마이징: ★ 표시 부분(환경 디렉토리·사전 스냅샷·잔여 확인).
# 안전      : CONFIRM=yes 일 때만 실제 destroy(ops --yes 시 자동 주입).
# =============================================================
set -u
CONFIRM="${CONFIRM:-}"
ENV_DIR="${ENV_DIR:-envs/dev}"          # ★ 환경 경로

echo "[infra] terraform destroy 준비 ($ENV_DIR)"

# ── ① 사전 안전 확인 ───────────────────────────────────────
# ★ RDS: skip_final_snapshot=true 라 destroy 시 데이터가 사라진다. 보존 필요하면 먼저 스냅샷.
#   aws rds create-db-snapshot --db-instance-identifier hailcast-dev-rds-postgres \
#       --db-snapshot-identifier hailcast-dev-final-$(date +%Y%m%d) --region ap-northeast-2
# ★ S3/ECR: force_destroy/force_delete=true 라 객체·이미지째 삭제됨(의도된 동작).

# ── ② 살아있는 ALB 잔여 가드 (manifest 를 안 지웠으면 여기서 멈춤) ──
LEFT_ALB=$(aws elbv2 describe-load-balancers --region ap-northeast-2 \
    --query "LoadBalancers[?contains(LoadBalancerName,'k8s')].LoadBalancerName" --output text 2>/dev/null || true)
if [ -n "$LEFT_ALB" ]; then
    echo "[infra] ⚠️ K8s 가 만든 ALB 가 아직 있음: $LEFT_ALB"
    echo "        → manifest teardown 을 먼저 끝내세요. VPC destroy 가 막힙니다."
    [ "$CONFIRM" = "yes" ] || { echo "[infra] 중단."; exit 1; }
fi

# ── ③ terraform destroy ────────────────────────────────────
cd "$ENV_DIR" || { echo "[infra] $ENV_DIR 없음"; exit 1; }
AUTO=""; [ "$CONFIRM" = "yes" ] && AUTO="-auto-approve"
echo "  \$ terraform destroy $AUTO"
if [ "$CONFIRM" = "yes" ]; then
    terraform destroy $AUTO
else
    echo "    (미실행 — 검토용. 실제 삭제는 CONFIRM=yes 또는 ops --yes)"
    terraform plan -destroy      # 무엇이 지워질지 미리보기만
fi

echo "[infra] 완료 — 잔여 리소스는 체크리스트로 확인(ENI·EBS·EIP·NAT·CloudWatch 로그그룹)."