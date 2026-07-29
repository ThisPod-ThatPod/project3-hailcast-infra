#!/bin/bash
# =============================================================
# 파일위치 : project3-hailcast-infra/scripts/teardown_infra.sh
# 역할     : infra 레포 terraform destroy 진입점 (ops 위임 대상)
# 호출     : ops/scripts/teardown.sh 가 manifest 다음(2번째)으로 부른다.
#            단독 실행(bash scripts/teardown_infra.sh)도 안전하도록 자체 계정 가드를 갖는다.
# 전제     : manifest teardown 이 먼저 끝나 ALB·ENI·Karpenter 노드가 없어야
#            VPC destroy 가 막히지 않는다(teardown_체크리스트.md 1장 원칙).
# 안전 계약 :
#   - 실제 destroy 는 CONFIRM=yes 일 때만.  (ops 가 destroy-all 시 주입)
#   - CUR 버킷에 객체가 남아있으면 무조건 중단 (BucketNotEmpty로 초반에 죽는 걸 미리 막음).
#   - ALB·Karpenter 노드가 살아있으면 실제 destroy 는 막힌다.
#     알고도 강행하려면 FORCE=yes (사람만 지정, 자동주입 금지).
#   - CONFIRM 없으면 plan -destroy(미리보기)만 → 실수 실행 안전.
# 커스터마이징(★) : ENV_DIR(환경 경로) · RDS 사전 스냅샷 정책 · CUR_HANDLING
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIRM="${CONFIRM:-}"                    # 진짜 지운다
FORCE="${FORCE:-}"                        # ALB/Karpenter 경고를 무시한다 (뜻을 분리)
ENV_DIR="${ENV_DIR:-envs/dev}"            # ★ 환경 경로
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
CUR_HANDLING="${CUR_HANDLING:-}"          # ★ 팀 결정(게이트①): keep(살림) | drop(버림) | 미정이면 빈 값 → 무조건 중단

info()  { echo "[infra] $*"; }
warn()  { echo "[infra][WARN] $*"; }
err()   { echo "[infra][ERROR] $*"; }

TARGET_DIR="$REPO_ROOT/$ENV_DIR"
[ -d "$TARGET_DIR" ] || { err "$TARGET_DIR 없음"; exit 1; }

# ── ⭐ 계정 가드 : ops를 거치지 않고 단독 실행돼도 오계정 사고를 막는다 ──
OPS_LIB="${OPS_LIB:-$REPO_ROOT/../project3-hailcast-ops/scripts/_lib.sh}"
if [ -f "$OPS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$OPS_LIB"
    if declare -f verify_project_account >/dev/null; then
        rc=0; verify_project_account || rc=$?
        case "$rc" in
            0) info "계정 확인: ${CURRENT_ACCOUNT:-OK} (프로젝트 계정)" ;;
            1) err "프로젝트 계정이 아님 — 중단합니다."; exit 1 ;;
            2) err "AWS 자격증명 없음/만료 — bash scripts/setup.sh 먼저 실행"; exit 1 ;;
        esac
    else
        warn "_lib.sh는 찾았지만 verify_project_account 함수가 없음 — 계정 가드 없이 진행(위험)"
    fi
else
    warn "$OPS_LIB 없음 — ops 레포가 형제 폴더에 없어 계정 가드를 건너뜀."
    warn "  (수동으로 'aws sts get-caller-identity'를 먼저 확인하세요)"
fi

info "terraform destroy 준비 ($TARGET_DIR)"

# ── ① CUR 버킷 가드 — 의존성 그래프상 가장 먼저 막히는 지점 ──────────
CUR_BUCKET=$(aws s3api list-buckets --region "$AWS_REGION" \
    --query "Buckets[?starts_with(Name,'hailcast-dev-cur')].Name" --output text 2>/dev/null || echo "")
if [ -n "$CUR_BUCKET" ]; then
    OBJ_COUNT=$(aws s3api list-objects-v2 --bucket "$CUR_BUCKET" --query 'length(Contents)' --output text 2>/dev/null || echo 0)
    [ "$OBJ_COUNT" = "None" ] && OBJ_COUNT=0
    if [ "$OBJ_COUNT" != "0" ]; then
        info "CUR 버킷(${CUR_BUCKET})에 객체 ${OBJ_COUNT}개 존재"
        case "$CUR_HANDLING" in
            keep)
                info "CUR_HANDLING=keep → terraform state rm으로 IaC 밖으로 뺍니다"
                if [ "$CONFIRM" = "yes" ]; then
                    aws cur delete-report-definition --report-name hailcast-dev-cur --region us-east-1 || true
                    ( cd "$TARGET_DIR" && terraform state rm \
                        module.storage.aws_s3_bucket.cur \
                        module.storage.aws_s3_bucket_policy.cur \
                        module.storage.aws_s3_bucket_lifecycle_configuration.cur \
                        module.storage.aws_s3_bucket_public_access_block.cur \
                        module.storage.aws_s3_bucket_server_side_encryption_configuration.cur \
                        module.storage.random_id.cur_suffix )
                    info "CUR 버킷을 IaC 밖 자원으로 전환 완료 — 규약서 5-9절에 기록할 것"
                else
                    info "  (미실행 — CONFIRM=yes일 때 state rm 수행)"
                fi
                ;;
            drop)
                err "CUR_HANDLING=drop은 modules/storage/cur.tf의 force_destroy=true PR을"
                err "  destroy 시작 '전에' 별도로 머지·apply 해야 합니다(이 스크립트가 대신 안 함 — 순서가 바뀌면 EKS·NAT·RDS 재생성 위험)."
                err "  teardown_체크리스트.md 7-3절대로 수동 진행 후 재실행하세요."
                exit 1
                ;;
            *)
                err "CUR_HANDLING이 정해지지 않았습니다(keep|drop) — 팀 게이트① 결정 후"
                err "  CUR_HANDLING=keep 또는 CUR_HANDLING=drop 으로 재실행하세요."
                exit 1
                ;;
        esac
    fi
fi

# ── ② ALB 잔여 가드 : '조회 실패' 와 'ALB 없음' 을 구분한다 ──────────
if ! LEFT_ALB=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
        --query "LoadBalancers[?contains(LoadBalancerName,'k8s')].LoadBalancerName" \
        --output text); then
    err "ALB 조회 실패 (자격증명·권한·리전 확인). 안전을 위해 중단합니다."
    exit 1
fi
if [ -n "$LEFT_ALB" ]; then
    warn "K8s가 만든 ALB가 아직 있습니다: $LEFT_ALB"
    warn "  manifest teardown을 먼저 끝내세요. ENI가 남아 VPC destroy가 막힙니다."
    if [ "$CONFIRM" = "yes" ] && [ "$FORCE" != "yes" ]; then
        err "실제 destroy를 중단합니다. (경고를 알고도 강행하려면 FORCE=yes)"
        exit 1
    fi
fi

# ── ③ Karpenter 노드 잔여 가드 ────────────────────────────────────
KARPENTER_NODES=$(aws ec2 describe-instances --region "$AWS_REGION" \
    --filters "Name=tag-key,Values=karpenter.sh/nodepool" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")
if [ -n "$KARPENTER_NODES" ]; then
    warn "Karpenter 노드가 아직 살아있습니다: $KARPENTER_NODES"
    warn "  manifest teardown이 경로 B(kubectl)였다면 karpenter Application에 finalizer가 없어"
    warn "  노드가 자동으로 안 지워집니다. 이대로 destroy하면 ENI가 서브넷 삭제를 막습니다."
    if [ "$CONFIRM" = "yes" ] && [ "$FORCE" != "yes" ]; then
        err "실제 destroy를 중단합니다."
        err "  강행하려면 FORCE=yes, 또는 먼저: aws ec2 terminate-instances --instance-ids $KARPENTER_NODES"
        exit 1
    fi
fi

cd "$TARGET_DIR"
terraform init -input=false               # 새 clone 에서도 destroy 가 되도록 (멱등)

# ── ★ (선택) RDS 데이터 보존이 필요하면 destroy 전에 수동 스냅샷 ──
#   RDS는 skip_final_snapshot=true라 destroy 시 자동 스냅샷이 없다(dev 데모 기본값).
#   팀 게이트③(RDS 스냅샷 뜰지)에서 "뜬다"로 정했을 때만 아래 주석 해제.
# aws rds create-db-snapshot \
#     --db-instance-identifier hailcast-dev-rds-postgres \
#     --db-snapshot-identifier hailcast-dev-final-$(date +%Y%m%d) \
#     --region "$AWS_REGION"
# aws rds wait db-snapshot-available --db-snapshot-identifier hailcast-dev-final-$(date +%Y%m%d) --region "$AWS_REGION"

if [ "$CONFIRM" = "yes" ]; then
    info "\$ terraform destroy -auto-approve"
    terraform destroy -auto-approve
    info "destroy 완료. 잔여 리소스 확인(ENI·EBS·EIP·NAT·로그그룹) — teardown_체크리스트.md 7-7절."
else
    info "(미실행 - 검토용. 실제 삭제는 CONFIRM=yes)"
    terraform plan -destroy
    info "미리보기만 했습니다. 실제로 지우려면 CONFIRM=yes 로 다시 실행하세요."
fi
