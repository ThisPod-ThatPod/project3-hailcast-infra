# eks 모듈 - irsa.tf
# IRSA(IAM Roles for Service Accounts) = 파드마다 발급하는 '제한된 사원증'.
#
# 원리: 파드의 SA 토큰(JWT)을 STS 가 클러스터 OIDC provider 로 검증해 임시 자격증명을 내준다.
#   노드 역할(iam.tf 의 node role)을 쓰면 그 노드 위 '모든' 파드가 같은 권한을 공유하지만,
#   IRSA 는 SA 단위로 쪼개므로 최소권한이 성립한다.
# 그래서 신뢰정책(assume_role_policy)에 OIDC provider ARN 이 박히고 → 이 파일은 eks 모듈에 산다
#   (별도 security 모듈로 빼면 OIDC 의존 때문에 생성 순서가 꼬인다 = chicken-egg. 규약서 §5-3).
#
# ⚠️ 이 PR 범위: 규약서 §5-3 의 IRSA 8종 중 '외부 ARN 이 필요 없는' 2종만 만든다.
#    나머지 6종(predict·call-api·worker·keda·karpenter·forecast)은 각각 S3·SQS·DynamoDB·
#    Karpenter 중단 큐의 ARN 을 정책 Resource 에 박아야 하는데, 그 리소스들이 아직 없다.
#    ARN 이 없다고 Resource = "*" 로 열어두면 최소권한이 무너지므로, 리소스가 머지된 뒤
#    아래 local.irsa_service_accounts 에 키를 추가하는 방식으로 이어붙인다.

locals {
  # 신뢰정책 condition 의 키는 issuer URL 에서 스킴을 뗀 호스트+경로 형태여야 한다.
  #   https://oidc.eks.ap-northeast-2.amazonaws.com/id/ABC → oidc.eks.ap-northeast-2.amazonaws.com/id/ABC
  # (STS 가 토큰의 iss 클레임을 이 문자열로 정규화해 대조한다)
  oidc_issuer_host = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")

  # 역할 키 → 그 역할을 맬 SA("네임스페이스:이름"). manifests 의 serviceaccount.yaml 과 맺는 계약(§5-3).
  # for_each 의 '키'는 여기 하드코딩된 문자열이라 plan 시점에 확정된다(apply 미상값 for_each 금지 원칙 준수).
  irsa_service_accounts = {
    lbctrl     = "kube-system:aws-load-balancer-controller"
    monitoring = "monitoring:monitoring-sa"
  }
}

# ── 공통 신뢰정책 ───────────────────────────────────────────
# 'OIDC provider 가 서명했고(Federated), 토큰의 sub 가 이 SA 이고, aud 가 sts 인' 경우만 assume 허용.
#
# ⚠️ aud 조건을 빼면 안 된다. sub 만 검사하면 같은 OIDC issuer 를 신뢰하는 다른 대상(audience)용
#    토큰으로도 역할을 맬 수 있어 confused-deputy 가 열린다. 두 조건은 항상 한 쌍이다.
data "aws_iam_policy_document" "irsa_assume" {
  for_each = local.irsa_service_accounts

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    # each.value 가 "kube-system:aws-load-balancer-controller" 이므로 아래가 곧
    # system:serviceaccount:kube-system:aws-load-balancer-controller 가 된다.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${each.value}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_service_accounts

  name               = "${local.name_prefix}-irsa-${each.key}" # hailcast-dev-irsa-lbctrl (§5-3)
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[each.key].json

  tags = merge(var.tags, { Name = "${local.name_prefix}-irsa-${each.key}" })
}

# ── 1) lbctrl — AWS Load Balancer Controller ────────────────
# Ingress 를 보고 ALB 를 만들고 대상그룹에 파드 IP 를 등록하는 애드온(설치는 manifests/ArgoCD 소관).
#
# 정책 본문은 손으로 줄이지 않고 upstream 원본을 그대로 벤더링한다:
#   출처: kubernetes-sigs/aws-load-balancer-controller · docs/install/iam_policy.json
#   임의로 action 을 쳐내면 Ingress 조정(reconcile)이 특정 경로에서만 조용히 실패한다.
# 원본이 Resource="*" 인 statement 들은 대부분 elasticloadbalancing:*Tag 조건으로 좁혀져 있고,
# 컨트롤러가 클러스터 밖 LB 를 건드리지 않도록 upstream 이 조건을 설계해 두었다.
resource "aws_iam_policy" "lbctrl" {
  name        = "${local.name_prefix}-irsa-lbctrl-policy"
  description = "AWS Load Balancer Controller 공식 IAM 정책(upstream iam_policy.json 원본)."
  policy      = file("${path.module}/policies/aws-load-balancer-controller.json")

  tags = merge(var.tags, { Name = "${local.name_prefix}-irsa-lbctrl-policy" })
}

resource "aws_iam_role_policy_attachment" "lbctrl" {
  role       = aws_iam_role.irsa["lbctrl"].name
  policy_arn = aws_iam_policy.lbctrl.arn
}

# ── 2) monitoring — CloudWatch 읽기 ─────────────────────────
# Prometheus 사이드카/exporter 가 CloudWatch 지표를 긁어온다. 읽기 전용이라 AWS 관리형으로 충분하다.
# (ARN 은 상수 → 별도 커스텀 정책을 만들 이유가 없다. YAGNI)
resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.irsa["monitoring"].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}
